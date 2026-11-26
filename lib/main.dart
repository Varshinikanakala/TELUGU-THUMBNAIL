import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// Colour and badge for each category (used by Free mode).
class CategoryStyle {
  final Color accent;
  final String badge;
  const CategoryStyle(this.accent, this.badge);
}

const Map<String, CategoryStyle> kCategories = {
  'News & Updates': CategoryStyle(Colors.redAccent, 'BREAKING'),
  'Vlog & Lifestyle': CategoryStyle(Colors.tealAccent, 'VLOG'),
  'Tech & App': CategoryStyle(Colors.lightBlueAccent, 'TECH'),
  'Motivation': CategoryStyle(Colors.amber, 'MOTIVATION'),
  'Gaming & Mass': CategoryStyle(Colors.purpleAccent, 'GAMING'),
};

const String kModel = 'gemini-3.1-flash-image';

class ThumbnailHomePage extends StatefulWidget {
  const ThumbnailHomePage({super.key});

  @override
  State<ThumbnailHomePage> createState() => _ThumbnailHomePageState();
}

class _ThumbnailHomePageState extends State<ThumbnailHomePage> {
  File? _selectedImage;
  Uint8List? _aiImageBytes;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _useAi = false; // Free mode is the default
  String _savedApiKey = '';
  String _selectedCategory = kCategories.keys.first;

  final TextEditingController _titleController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  final GlobalKey _thumbKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadApiKey();
    _titleController.addListener(() => setState(() {})); // live preview
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _toast(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ---------------- API key ----------------

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _savedApiKey = prefs.getString('gemini_api_key') ?? '');
  }

  Future<void> _saveApiKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key.trim());
    setState(() => _savedApiKey = key.trim());
  }

  void _showApiKeyDialog() {
    final controller = TextEditingController(text: _savedApiKey);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gemini API Key (AI mode)'),
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
                'Important',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber),
              ),
              const SizedBox(height: 6),
              const Text(
                'AI image generation does not work on the free API tier. '
                'Your Google AI Studio project must have billing enabled, '
                'otherwise you will get error 429.\n\n'
                'Free mode works without any key.\n\n'
                'Your key is saved only on this device.',
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
              _toast('API Key saved!');
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

  // ---------------- Photo ----------------

  Future<void> _pickImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600, // smaller upload, faster
      imageQuality: 85, // saves as JPEG
    );
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
        _aiImageBytes = null;
      });
    }
  }

  // ---------------- AI mode ----------------

  Future<void> _generateWithAi() async {
    if (_savedApiKey.isEmpty) {
      _showApiKeyDialog();
      return;
    }
    if (_selectedImage == null) {
      _toast('Please select a photo first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _aiImageBytes = null;
    });

    try {
      final bytes = await _selectedImage!.readAsBytes();
      final headline = _titleController.text.trim();
      final prompt =
          'Create a high-click-through-rate YouTube thumbnail using the person/subject from this image. '
          'Keep the person\'s face and identity exactly the same. '
          'Style/Category: $_selectedCategory. '
          '${headline.isNotEmpty ? 'Add bold, eye-catching thumbnail text exactly as written: "$headline". ' : ''}'
          'Use dramatic lighting, vibrant background, high contrast and a professional composition.';

      final response = await http
          .post(
            Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$kModel:generateContent',
            ),
            headers: {
              'Content-Type': 'application/json',
              'x-goog-api-key': _savedApiKey,
            },
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inlineData': {
                        'mimeType': 'image/jpeg',
                        'data': base64Encode(bytes),
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'responseModalities': ['TEXT', 'IMAGE'],
                'imageConfig': {'aspectRatio': '16:9'},
              }
            }),
          )
          .timeout(const Duration(seconds: 120));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final parts = data['candidates']?[0]?['content']?['parts'] as List?;
        Uint8List? imageBytes;
        for (final part in parts ?? []) {
          final inline = part['inlineData'];
          if (inline != null && inline['data'] != null) {
            imageBytes = base64Decode(inline['data']);
            break;
          }
        }
        if (imageBytes == null) {
          throw Exception('No image returned. Try a different photo or text.');
        }
        setState(() => _aiImageBytes = imageBytes);
      } else if (response.statusCode == 429) {
        throw Exception(
          'Quota 0 (error 429). AI images need a Gemini project with billing enabled. '
          'Switch to Free mode to make thumbnails without a key.',
        );
      } else {
        String reason = 'Unknown error';
        try {
          reason = jsonDecode(response.body)['error']['message'] ?? reason;
        } catch (_) {}
        throw Exception('API Error ${response.statusCode}: $reason');
      }
    } catch (e) {
      _toast('$e'.replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- Save ----------------

  /// Turns the Free mode preview into a 1280px-wide PNG.
  Future<Uint8List?> _captureFreeThumbnail() async {
    final boundary =
        _thumbKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;
    final image = await boundary.toImage(pixelRatio: 1280 / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  Future<void> _saveToGallery() async {
    setState(() => _isSaving = true);
    try {
      final bytes = _useAi ? _aiImageBytes : await _captureFreeThumbnail();
      if (bytes == null) throw Exception('Nothing to save yet.');
      await Gal.putImageBytes(
        bytes,
        name: 'YT_Thumb_${DateTime.now().millisecondsSinceEpoch}',
      );
      _toast('Thumbnail saved to Gallery!', color: Colors.green);
    } catch (e) {
      _toast('Failed to save: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------------- Free mode preview ----------------

  Widget _outlinedText(String text, double size, Color fill) {
    final base = TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w900,
      height: 1.1,
    );
    return Stack(
      children: [
        Text(
          text,
          maxLines: 3,
          style: base.copyWith(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = size / 7
              ..color = Colors.black,
          ),
        ),
        Text(text, maxLines: 3, style: base.copyWith(color: fill)),
      ],
    );
  }

  Widget _freeThumbnail() {
    final style = kCategories[_selectedCategory]!;
    final headline = _titleController.text.trim();

    return RepaintBoundary(
      key: _thumbKey,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: LayoutBuilder(
          builder: (context, box) {
            final w = box.maxWidth;
            return Stack(
              fit: StackFit.expand,
              children: [
                Image.file(_selectedImage!, fit: BoxFit.cover),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.85),
                      ],
                    ),
                  ),
                ),
                // Coloured frame
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: style.accent, width: w * 0.012),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(w * 0.04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: w * 0.02,
                          vertical: w * 0.006,
                        ),
                        color: style.accent,
                        child: Text(
                          style.badge,
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: w * 0.035,
                          ),
                        ),
                      ),
                      SizedBox(height: w * 0.02),
                      if (headline.isNotEmpty)
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: w * 0.6),
                          child: _outlinedText(headline, w * 0.075, Colors.white),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final hasResult = _useAi ? _aiImageBytes != null : _selectedImage != null;

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
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Free mode'),
                  icon: Icon(Icons.brush),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('AI mode'),
                  icon: Icon(Icons.auto_awesome),
                ),
              ],
              selected: {_useAi},
              onSelectionChanged: (s) => setState(() => _useAi = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _useAi
                  ? 'AI mode needs a Gemini key from a billing-enabled project.'
                  : 'Free mode works offline. Telugu text shows perfectly.',
              style: const TextStyle(fontSize: 12, color: Colors.white60),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 180,
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
              items: kCategories.keys
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
                labelText: 'Thumbnail Text (Telugu or English)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            if (_useAi)
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _generateWithAi,
                icon: _isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isLoading ? 'Generating...' : 'Generate with AI'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            if (hasResult) ...[
              const SizedBox(height: 20),
              const Text(
                'Your Thumbnail:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _useAi
                    ? AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Image.memory(_aiImageBytes!, fit: BoxFit.cover),
                      )
                    : _freeThumbnail(),
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
