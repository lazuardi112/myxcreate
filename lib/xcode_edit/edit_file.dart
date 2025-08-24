import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:myxcreate/code/HtmlRenderPage.dart';

class EditFilePage extends StatefulWidget {
  final String fileName;
  final String filePath;
  final String initialContent;

  const EditFilePage({
    Key? key,
    required this.fileName,
    required this.filePath,
    required this.initialContent,
  }) : super(key: key);

  @override
  _EditFilePageState createState() => _EditFilePageState();
}

class _EditFilePageState extends State<EditFilePage> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialContent);
  }

  Future<void> _saveFile() async {
    final file = File(widget.filePath);
    await file.writeAsString(_controller.text);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File berhasil disimpan')),
    );
    Navigator.pop(context);
  }

  void _resetCode() {
    setState(() {
      _controller.text = widget.initialContent;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File direset')),
    );
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _controller.text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File disalin ke clipboard')),
    );
  }

  void _renderHtml() {
  Navigator.push(
    context,
    PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => HtmlRenderPage(
        htmlContent: _controller.text,
      ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        const begin = Offset(1.0, 0.0); // Dari kanan ke kiri
        const end = Offset.zero;
        const curve = Curves.ease;

        final tween =
            Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.blueGrey.shade900,
        title: Row(
          children: [
            Icon(Icons.folder, color: Colors.white70),
            SizedBox(width: 8),
            Text('File', style: TextStyle(color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(icon: Icon(Icons.copy, color: Colors.white70), onPressed: _copyCode),
          IconButton(icon: Icon(Icons.refresh, color: Colors.white70), onPressed: _resetCode),
          IconButton(icon: Icon(Icons.save, color: Colors.white70), onPressed: _saveFile),
        ],
      ),
      body: Column(
        children: [
          Container(
            color: Colors.blueGrey.shade800,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                Text('Editing: ${widget.fileName}', style: TextStyle(color: Colors.white70)),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.play_arrow, color: Colors.white70),
                  onPressed: _renderHtml,
                ),
                SizedBox(width: 8),
                Icon(Icons.more_vert, color: Colors.white70),
              ],
            ),
          ),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(8),
              color: Colors.black87,
              child: TextField(
                controller: _controller,
                maxLines: null,
                style: TextStyle(fontSize: 16, color: Colors.white, fontFamily: "monospace"),
                decoration: InputDecoration(
                  border: InputBorder.none,
                ),
                keyboardType: TextInputType.multiline,
              ),
            ),
          ),
          Container(
            color: Colors.blueGrey.shade900,
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildShortcutButton("<div>"),
                  _buildShortcutButton("<a>"),
                  _buildShortcutButton("<img>"),
                  _buildShortcutButton("[class]"),
                  _buildShortcutButton("[id]"),
                  _buildShortcutButton("html:"),
                  _buildShortcutButton("=\"\""),
                  _buildShortcutButton("<"),
                  _buildShortcutButton(">"),
                  _buildShortcutButton("</"),
                  _buildShortcutButton("-"),
                  _buildShortcutButton("<!-- -->"),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShortcutButton(String text) {
    return ElevatedButton(
      onPressed: () {
        final currentText = _controller.text;
        final cursorPos = _controller.selection.baseOffset;
        final newText = currentText.replaceRange(cursorPos, cursorPos, text);
        _controller.text = newText;
        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: cursorPos + text.length),
        );
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade800,
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      child: Text(text, style: TextStyle(color: Colors.white70, fontSize: 12)),
    );
  }
}