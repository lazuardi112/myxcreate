// home.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'detail.dart';

// Package untuk PDF/printing
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _books = [];
  String _searchQuery = "";
  Map<int, bool> _exporting = {}; // track export state per book

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString("books");
    if (data != null) {
      setState(() {
        _books = List<Map<String, dynamic>>.from(json.decode(data));
      });
    }
  }

  Future<void> _saveBooks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("books", json.encode(_books));
  }

  void _addBookDialog({Map<String, dynamic>? book, int? index}) {
    final titleController = TextEditingController(
      text: book != null ? book["title"] : "",
    );
    final authorController = TextEditingController(
      text: book != null ? book["author"] : "",
    );

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(book == null ? "Tambah Buku" : "Edit Buku"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: const InputDecoration(labelText: "Judul Buku"),
            ),
            TextField(
              controller: authorController,
              decoration: const InputDecoration(labelText: "Penulis"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () {
              if (titleController.text.isNotEmpty &&
                  authorController.text.isNotEmpty) {
                if (book == null) {
                  _books.add({
                    "id": DateTime.now().millisecondsSinceEpoch,
                    "title": titleController.text,
                    "author": authorController.text,
                  });
                } else {
                  _books[index!] = {
                    "id": book["id"],
                    "title": titleController.text,
                    "author": authorController.text,
                  };
                }
                _saveBooks();
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text("Simpan"),
          ),
        ],
      ),
    );
  }

  void _deleteBook(int index) {
    final removed = _books.removeAt(index);
    _saveBooks();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Buku "${removed['title']}" dihapus')),
    );
  }

  Future<void> _exportBookToPdf(Map<String, dynamic> book) async {
    final id = book['id'] as int;
    try {
      setState(() => _exporting[id] = true);

      final prefs = await SharedPreferences.getInstance();
      final pagesData = prefs.getString('book_content_$id');
      List<String> pages;
      if (pagesData != null) {
        pages = List<String>.from(json.decode(pagesData));
      } else {
        pages = [''];
      }

      final doc = pw.Document();

      // Buat satu section per halaman (akan otomatis pecah kalau terlalu panjang)
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context context) {
            final List<pw.Widget> content = [];
            for (var i = 0; i < pages.length; i++) {
              content.add(
                pw.Header(level: 1, child: pw.Text('Halaman ${i + 1}')),
              );
              final text = pages[i].isNotEmpty ? pages[i] : '(Halaman kosong)';
              content.add(
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 12),
                  child: pw.Text(
                    text,
                    style: pw.TextStyle(fontSize: 12),
                    textAlign: pw.TextAlign.justify,
                  ),
                ),
              );
              // pemisah visual antar halaman di PDF
              content.add(pw.Divider());
            }
            return content;
          },
        ),
      );

      final bytes = await doc.save();

      // Menggunakan printing untuk share / save
      await Printing.sharePdf(bytes: bytes, filename: '${book['title']}.pdf');

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Berhasil mengekspor "${book['title']}" ke PDF'),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal mengekspor: $e')));
    } finally {
      setState(() => _exporting[id] = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredBooks = _books
        .where(
          (b) => b["title"].toString().toLowerCase().contains(
            _searchQuery.toLowerCase(),
          ),
        )
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FF),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        title: const Text(
          "Daftar Buku",
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search bar modern
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFB2FEFA), Color(0xFF0ED2F7)],
                  ),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  onChanged: (v) => setState(() => _searchQuery = v),
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: Colors.white70),
                    hintText: "Cari judul buku...",
                    hintStyle: const TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            // Header kecil
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  const Text(
                    'Hasil',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${filteredBooks.length} buku',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () async {
                      // Refresh manual
                      await _loadBooks();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Daftar diperbarui')),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // List buku
            Expanded(
              child: filteredBooks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.book_outlined,
                            size: 64,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Belum ada buku',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: filteredBooks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final book = filteredBooks[index];
                        final int id = book['id'] as int;
                        final bool exporting = _exporting[id] ?? false;

                        // warna gradien acak berdasarkan index untuk variasi
                        final gradients = [
                          [Color(0xFFFFD6A5), Color(0xFFFFABAB)],
                          [Color(0xFFB2FEFA), Color(0xFF0ED2F7)],
                          [Color(0xFFC6FFDD), Color(0xFFFBD786)],
                          [Color(0xFFB4EC51), Color(0xFF429321)],
                        ];
                        final grad = gradients[index % gradients.length];

                        return GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DetailPage(bookId: id),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: grad),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Icon / cover
                                Container(
                                  width: 56,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: Colors.white24,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black12,
                                        blurRadius: 6,
                                        offset: Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      (book['title'] ?? '')
                                          .toString()
                                          .split(' ')
                                          .map((w) => w.isNotEmpty ? w[0] : '')
                                          .take(2)
                                          .join()
                                          .toUpperCase(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Title & author
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        book['title'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        book['author'] ?? '',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.black87,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.notes,
                                            size: 14,
                                            color: Colors.black54,
                                          ),
                                          const SizedBox(width: 6),
                                          FutureBuilder<String>(
                                            future: _getPageCountText(
                                              book['id'] as int,
                                            ),
                                            builder: (context, snap) {
                                              final txt = snap.hasData
                                                  ? snap.data!
                                                  : '...';
                                              return Text(
                                                txt,
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.black54,
                                                ),
                                              );
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                // Buttons: download, edit, delete
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    exporting
                                        ? SizedBox(
                                            width: 36,
                                            height: 36,
                                            child:
                                                const CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                          )
                                        : IconButton(
                                            onPressed: () async {
                                              await _exportBookToPdf(book);
                                            },
                                            icon: const Icon(
                                              Icons.download_rounded,
                                            ),
                                            tooltip:
                                                'Download semua halaman ke PDF',
                                          ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.edit,
                                            color: Colors.blue,
                                          ),
                                          onPressed: () {
                                            // Need to find original index in _books (filteredBooks uses subset)
                                            final originalIndex = _books
                                                .indexWhere(
                                                  (b) => b['id'] == book['id'],
                                                );
                                            _addBookDialog(
                                              book: book,
                                              index: originalIndex >= 0
                                                  ? originalIndex
                                                  : null,
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () {
                                            final originalIndex = _books
                                                .indexWhere(
                                                  (b) => b['id'] == book['id'],
                                                );
                                            if (originalIndex >= 0)
                                              _deleteBook(originalIndex);
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.teal,
        onPressed: () => _addBookDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<String> _getPageCountText(int bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final pagesData = prefs.getString('book_content_$bookId');
    if (pagesData == null) return '0 halaman';
    try {
      final pages = List<String>.from(json.decode(pagesData));
      return '${pages.length} halaman';
    } catch (_) {
      return '0 halaman';
    }
  }
}
