import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

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

  String _selectedCategory = 'News & Updates';
  final List<String> _categories = [
    'News & Updates',
    'Vlog & Lifestyle',
    'Tech & App',
    'Motivation',
    'Gaming & Mass',
  ];

  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _titleController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

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
    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your Gemini API Key first!')),
      );
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
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-image:generateContent?key=$apiKey',
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
        throw Exception('API Error ${response.statusCode}: ${response.body}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI YouTube Thumbnail Maker'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _apiKeyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key (AIza...)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.key),
              ),
            ),
            const SizedBox(height: 16),
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
            ],
          ],
        ),
      ),
    );
  }
}
