// detail.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DetailPage extends StatefulWidget {
  final int bookId;
  const DetailPage({super.key, required this.bookId});

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  Map<String, dynamic>? _book;
  List<String> _pages = [];
  int _currentPage = 0;
  Set<int> _bookmarks = {};

  final TextEditingController _editController = TextEditingController();
  late PageController _pageViewController;

  bool _isEditing = false;
  bool _isLoading = true;

  Timer? _saveDebounce;
  bool _listenerAdded = false;

  // UI style
  final Color _paperColor = const Color(0xFFFFF8E1); // cream paper
  final Color _lineColor = Colors.blueAccent; // ruled lines

  @override
  void initState() {
    super.initState();
    _pageViewController = PageController(initialPage: _currentPage);
    _loadAll();
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    _editController.dispose();
    _pageViewController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();

    // load book metadata
    final data = prefs.getString('books');
    if (data != null) {
      try {
        final books = List<Map<String, dynamic>>.from(json.decode(data));
        final found = books.firstWhere(
          (b) => b['id'] == widget.bookId,
          orElse: () => {},
        );
        _book = found.isNotEmpty ? found : null;
      } catch (e) {
        _book = null;
      }
    }

    // pages
    final pagesData = prefs.getString('book_content_${widget.bookId}');
    if (pagesData != null) {
      try {
        _pages = List<String>.from(json.decode(pagesData));
      } catch (e) {
        _pages = [''];
      }
    } else {
      _pages = [''];
    }

    // bookmarks
    final bookmarkData = prefs.getString('book_bookmark_${widget.bookId}');
    if (bookmarkData != null) {
      try {
        _bookmarks = Set<int>.from(json.decode(bookmarkData));
      } catch (e) {
        _bookmarks = {};
      }
    }

    // last-read page
    final last = prefs.getInt('book_last_${widget.bookId}');
    if (last != null && last >= 0 && last < _pages.length) {
      _currentPage = last;
      _pageViewController = PageController(initialPage: _currentPage);
    }

    // set controller
    _editController.text = _pages.isNotEmpty ? _pages[_currentPage] : '';

    // add listener once
    if (!_listenerAdded) {
      _editController.addListener(_onTextChanged);
      _listenerAdded = true;
    }

    setState(() {
      _isLoading = false;
    });
  }

  void _onTextChanged() {
    if (!_isEditing) return; // only save in edit mode

    // update in-memory
    if (_currentPage < 0) return;
    while (_pages.length <= _currentPage) _pages.add('');
    _pages[_currentPage] = _editController.text;

    // Debounce heavy writes (very short delay so "langsung" terasa instant)
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), () {
      _savePages();
    });
  }

  Future<void> _savePages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('book_content_${widget.bookId}', json.encode(_pages));
  }

  Future<void> _saveBookmarks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'book_bookmark_${widget.bookId}',
      json.encode(_bookmarks.toList()),
    );
  }

  Future<void> _saveLastRead() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('book_last_${widget.bookId}', _currentPage);
  }

  void _toggleBookmark() {
    setState(() {
      if (_bookmarks.contains(_currentPage)) {
        _bookmarks.remove(_currentPage);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Bookmark dihapus')));
      } else {
        _bookmarks.add(_currentPage);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Disimpan ke bookmark')));
      }
    });
    _saveBookmarks();
  }

  void _enterEditMode() {
    setState(() {
      _isEditing = true;
      while (_pages.length <= _currentPage) _pages.add('');
      _editController.text = _pages[_currentPage];
      _editController.selection = TextSelection.fromPosition(
        TextPosition(offset: _editController.text.length),
      );
    });
  }

  void _exitEditMode() {
    // ensure last content saved
    if (_currentPage < _pages.length) {
      _pages[_currentPage] = _editController.text;
      _savePages();
    }
    setState(() {
      _isEditing = false;
    });
    // jump pageview to current
    _pageViewController.jumpToPage(_currentPage);
  }

  void _addBlankPageAfterCurrent({bool openInEdit = false}) {
    setState(() {
      final insertIndex = _currentPage + 1;
      _pages.insert(insertIndex, '');
      _savePages();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Halaman baru ditambahkan')));
      _goToPage(insertIndex);
      if (openInEdit) _enterEditMode();
    });
  }

  void _deleteCurrentPage() {
    if (_pages.isEmpty) return;
    final removedIndex = _currentPage;
    if (_pages.length == 1) {
      setState(() {
        _pages[0] = '';
        _savePages();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Halaman dikosongkan')));
      });
      return;
    }

    setState(() {
      _pages.removeAt(removedIndex);

      // adjust bookmarks
      final newBookmarks = <int>{};
      for (final b in _bookmarks) {
        if (b == removedIndex) continue; // removed
        if (b > removedIndex) newBookmarks.add(b - 1);
        if (b < removedIndex) newBookmarks.add(b);
      }
      _bookmarks = newBookmarks;
      _saveBookmarks();

      if (_currentPage >= _pages.length) _currentPage = _pages.length - 1;
      _savePages();
      _pageViewController.jumpToPage(_currentPage);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Halaman dihapus')));
    });
  }

  void _goToPage(int page) {
    if (page < 0 || page >= _pages.length) return;
    setState(() {
      _currentPage = page;
      if (_isEditing) {
        _editController.text = _pages[_currentPage];
        _editController.selection = TextSelection.fromPosition(
          TextPosition(offset: _editController.text.length),
        );
      } else {
        _pageViewController.animateToPage(
          _currentPage,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
    _saveLastRead();
  }

  Widget _buildBookPage(String text, int pageIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 12.0),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 900),
          decoration: BoxDecoration(
            color: _paperColor,
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: CustomPaint(
            painter: _LinedPaperPainter(lineColor: _lineColor),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Text(
                        text.isNotEmpty ? text : '(Halaman kosong)',
                        textAlign: TextAlign.justify,
                        style: const TextStyle(
                          fontSize: 16,
                          height: 1.6,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Halaman ${pageIndex + 1}',
                        style: const TextStyle(color: Colors.grey),
                      ),
                      if (_bookmarks.contains(pageIndex))
                        const Icon(
                          Icons.bookmark,
                          size: 18,
                          color: Colors.amber,
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReadMode() {
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageViewController,
            itemCount: _pages.length,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
              _saveLastRead();
            },
            itemBuilder: (context, index) {
              return _buildBookPage(_pages[index], index);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _currentPage > 0
                    ? () => _goToPage(_currentPage - 1)
                    : null,
                icon: const Icon(Icons.chevron_left),
                label: const Text('Lihat Sebelumnya'),
              ),
              const SizedBox(width: 8),
              Text('${_currentPage + 1} / ${_pages.length}'),
              const Spacer(),
              IconButton(
                onPressed: _toggleBookmark,
                icon: Icon(
                  _bookmarks.contains(_currentPage)
                      ? Icons.bookmark
                      : Icons.bookmark_border,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _currentPage < _pages.length - 1
                    ? () => _goToPage(_currentPage + 1)
                    : null,
                icon: const Icon(Icons.chevron_right),
                label: const Text('Lihat Selanjutnya'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEditMode() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: _exitEditMode,
                icon: const Icon(Icons.check),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  _addBlankPageAfterCurrent(openInEdit: true);
                },
                icon: const Icon(Icons.note_add),
                label: const Text('Halaman Baru'),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _deleteCurrentPage,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Hapus Halaman'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              decoration: BoxDecoration(
                color: _paperColor,
                borderRadius: BorderRadius.circular(6),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: CustomPaint(
                painter: _LinedPaperPainter(lineColor: _lineColor),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18.0,
                    vertical: 14.0,
                  ),
                  child: TextField(
                    controller: _editController,
                    keyboardType: TextInputType.multiline,
                    maxLines: null,
                    expands: true,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Mulai tulis di halaman ini...',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            children: [
              ElevatedButton(
                onPressed: _currentPage > 0
                    ? () {
                        setState(() {
                          // save handled by listener
                          _goToPage(_currentPage - 1);
                          _editController.text = _pages[_currentPage];
                        });
                      }
                    : null,
                child: const Text('Sebelumnya'),
              ),
              const SizedBox(width: 8),
              Text('${_currentPage + 1} / ${_pages.length}'),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    if (_currentPage < _pages.length - 1) {
                      _goToPage(_currentPage + 1);
                    } else {
                      _pages.add('');
                      _goToPage(_pages.length - 1);
                      _savePages();
                    }
                    _editController.text = _pages[_currentPage];
                  });
                },
                child: const Text('Selanjutnya'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Memuat...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_book == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Buku')),
        body: const Center(child: Text('Buku tidak ditemukan')),
      );
    }

    return WillPopScope(
      onWillPop: () async {
        if (_isEditing) {
          _exitEditMode();
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_book!['title'] ?? 'Detail Buku'),
          backgroundColor: Colors.teal,
          actions: [
            // Tombol edit sekarang ada di AppBar (menggantikan FAB)
            IconButton(
              onPressed: () {
                if (_isEditing) {
                  _exitEditMode();
                } else {
                  _enterEditMode();
                }
              },
              icon: Icon(_isEditing ? Icons.check : Icons.edit),
              tooltip: _isEditing ? 'Selesai' : 'Edit Buku',
            ),
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) {
                    return AlertDialog(
                      title: const Text('Daftar Halaman'),
                      content: SizedBox(
                        width: double.maxFinite,
                        child: ListView.builder(
                          itemCount: _pages.length,
                          itemBuilder: (context, i) {
                            return ListTile(
                              leading: _bookmarks.contains(i)
                                  ? const Icon(
                                      Icons.bookmark,
                                      color: Colors.amber,
                                    )
                                  : const Icon(Icons.description),
                              title: Text('Halaman ${i + 1}'),
                              subtitle: Text(
                                _pages[i].replaceAll('\n', ' ').trim(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () {
                                Navigator.pop(context);
                                _goToPage(i);
                                if (_isEditing) {
                                  _editController.text = _pages[_currentPage];
                                }
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                );
              },
              icon: const Icon(Icons.view_list),
              tooltip: 'Daftar Halaman',
            ),
          ],
        ),
        body: Container(
          color: Colors.grey[200],
          child: _isEditing ? _buildEditMode() : _buildReadMode(),
        ),
        // FAB dihapus karena tombol edit sudah dipindah ke AppBar
      ),
    );
  }
}

// Painter untuk membuat garis-garis seperti kertas bergaris
class _LinedPaperPainter extends CustomPainter {
  final Color lineColor;
  final double lineHeight;
  final double leftMargin;

  _LinedPaperPainter({
    required this.lineColor,
    this.lineHeight = 28,
    this.leftMargin = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor.withOpacity(0.20)
      ..strokeWidth = 1.0;

    double y = 20; // start a little lower for top margin
    while (y < size.height - 20) {
      canvas.drawLine(
        Offset(12 + leftMargin, y),
        Offset(size.width - 12, y),
        paint,
      );
      y += lineHeight;
    }

    // subtle vertical margin line (like ruled notebook)
    final vertPaint = Paint()..color = lineColor.withOpacity(0.06);
    canvas.drawLine(Offset(12, 12), Offset(12, size.height - 12), vertPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
