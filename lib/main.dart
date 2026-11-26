import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gal/gal.dart';

void main() {
  runApp(const AutoThumbnailApp());
}

class AutoThumbnailApp extends StatelessWidget {
  const AutoThumbnailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Thumbnail Maker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.amber,
          brightness: Brightness.dark,
        ),
      ),
      home: const ThumbnailHomePage(),
    );
  }
}

class ThumbnailHomePage extends StatefulWidget {
  const ThumbnailHomePage({super.key});

  @override
  State<ThumbnailHomePage> createState() => _ThumbnailHomePageState();
}

class _ThumbnailHomePageState extends State<ThumbnailHomePage> {
  File? _selectedImage;
  Uint8List? _generatedImageBytes;
  bool _isLoading = false;
  bool _isSaving = false;
  String _savedApiKey = '';

  String _selectedCategory = 'News & Updates';
  final List<String> _categories = [
    'News & Updates',
    'Vlog & Lifestyle',
    'Tech & App',
    'Motivation',
    'Gaming & Mass',
  ];

  final TextEditingController _titleController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('gemini_api_key') ?? '';
    setState(() {
      _savedApiKey = key;
    });
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    setState(() {
      _savedApiKey = key.trim();
    });
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: _savedApiKey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Setup Gemini API Key'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Paste your API Key (AIza...)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'How to get a FREE API Key:',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
              ),
              const SizedBox(height: 6),
              const Text(
                '1. Open aistudio.google.com in your browser.\n'
                '2. Sign in with your Google account.\n'
                '3. Tap "Get API key" -> "Create API key".\n'
                '4. Copy the key and paste it above.\n\n'
                'Your key is saved only on your device.',
                style: TextStyle(fontSize: 13, color: Colors.white70),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              _saveApiKey(controller.text);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('API Key saved!')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Save Key'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
        _generatedImageBytes = null;
      });
    }
  }

  Future<void> _generateThumbnail() async {
    if (_savedApiKey.isEmpty) {
      _showApiKeyDialog();
      return;
    }

    if (_selectedImage == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a photo first!')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _generatedImageBytes = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(bytes);
      final headline = _titleController.text.trim();

      final prompt =
          'Create a high-click-through-rate 16:9 YouTube thumbnail using the person/subject from this image. '
          'Keep the person\'s face and identity exactly the same. '
          'Style/Category: $_selectedCategory. '
          '${headline.isNotEmpty ? 'Add bold, eye-catching 3D thumbnail text: "$headline". ' : ''}'
          'Use dramatic studio lighting, vibrant background, high contrast, and professional YouTube thumbnail composition.';

      final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent?key=$_savedApiKey',
      );

      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
                {
                  'inlineData': {
                    'mimeType': 'image/jpeg',
                    'data': base64Image,
                  }
                }
              ]
            }
          ],
          'generationConfig': {
            'responseModalities': ['TEXT', 'IMAGE'],
          }
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final parts = data['candidates']?[0]?['content']?['parts'] as List?;
        Uint8List? imageBytes;

        if (parts != null) {
          for (final part in parts) {
            if (part['inlineData'] != null && part['inlineData']['data'] != null) {
              imageBytes = base64Decode(part['inlineData']['data']);
              break;
            }
          }
        }

        if (imageBytes != null) {
          setState(() {
            _generatedImageBytes = imageBytes;
          });
        } else {
          throw Exception('No image returned by Gemini. Try again.');
        }
      } else {
        throw Exception('API Error ${response.statusCode}: Check your API Key or Quota.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveToGallery() async {
    if (_generatedImageBytes == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      await Gal.putImageBytes(
        _generatedImageBytes!,
        name: 'YT_Thumb_${DateTime.now().millisecondsSinceEpoch}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Thumbnail saved to Gallery!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Thumbnail Maker'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: _showApiKeyDialog,
            icon: Icon(
              Icons.key,
              color: _savedApiKey.isEmpty ? Colors.redAccent : Colors.greenAccent,
            ),
            tooltip: 'Setup API Key',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_savedApiKey.isEmpty)
              Card(
                color: Colors.amber.withOpacity(0.15),
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: const Icon(Icons.key, color: Colors.amber),
                  title: const Text('API Key Required'),
                  subtitle: const Text('Tap here to add your free Gemini API Key'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: _showApiKeyDialog,
                ),
              ),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withOpacity(0.6)),
                ),
                child: _selectedImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Image.file(_selectedImage!, fit: BoxFit.cover),
                      )
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate, size: 48, color: Colors.amber),
                          SizedBox(height: 8),
                          Text('Tap here to select a photo'),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                labelText: 'Thumbnail Category',
                border: OutlineInputBorder(),
              ),
              items: _categories
                  .map((cat) => DropdownMenuItem(value: cat, child: Text(cat)))
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedCategory = val);
              },
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'Thumbnail Text (Optional - e.g. Big Update!)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _generateThumbnail,
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isLoading ? 'Generating Thumbnail...' : 'Generate Thumbnail'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 24),
            if (_generatedImageBytes != null) ...[
              const Text(
                'Generated Thumbnail:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(_generatedImageBytes!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveToGallery,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download),
                label: Text(_isSaving ? 'Saving...' : 'Save to Gallery'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
