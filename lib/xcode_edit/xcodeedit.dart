import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';
import 'dart:io';
import 'edit_file.dart';

class XcodeEditPage extends StatefulWidget {
  final List<dynamic>? currentItems;
  final String? currentPath;
  final String? folderDibuka;

  // Updated constructor to include folderDibuka
  XcodeEditPage({this.currentItems, this.currentPath, this.folderDibuka});

  @override
  _XcodeEditPageState createState() => _XcodeEditPageState();
}

class _XcodeEditPageState extends State<XcodeEditPage> {
  List<dynamic> items = [];
  List<dynamic> filteredItems = [];
  String currentPath = "root";
  late Directory appDocDirectory;

  final List<String> allowedExtensions = [
    '.html',
    '.php',
    '.js',
    '.css',
    '.sql',
    '.dart',
    '.py',
    '.java',
    '.c',
    '.cpp',
    '.json',
    '.xml'
  ];

  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    currentPath = widget.folderDibuka ?? "Ruang Kerja";
    _initDirectory();
    searchController.addListener(_filterItems);
  }

  Future<void> _initDirectory() async {
    appDocDirectory = await getApplicationDocumentsDirectory();
    if (widget.currentItems != null) {
      setState(() {
        items = widget.currentItems!;
        _sortItems();
        filteredItems = items;
      });
    } else {
      final file = File('${appDocDirectory.path}/file_folder_list.json');
      if (await file.exists()) {
        final data = await file.readAsString();
        setState(() {
          items = jsonDecode(data);
          _sortItems();
          filteredItems = items;
        });
      }
    }
  }

  void _sortItems() {
    // Sort items to put folders at the top
    items.sort((a, b) {
      if (a['type'] == 'folder' && b['type'] != 'folder') return -1;
      if (a['type'] != 'folder' && b['type'] == 'folder') return 1;
      return 0;
    });
  }

  Future<void> _saveItems() async {
    final file = File('${appDocDirectory.path}/file_folder_list.json');
    await file.writeAsString(jsonEncode(items));
  }

  void _addItem(String name, String type) {
    final newItem = {
      "title": name,
      "type": type,
      "children": type == "folder" ? [] : null
    };
    setState(() {
      items.add(newItem);
      _sortItems();
      filteredItems = items;
    });

    if (type == "file") {
      final fullPath = '$currentPath/$name';
      final file = File('${appDocDirectory.path}/$fullPath');
      file.createSync(recursive: true);
    }

    _saveItems();
  }

  void _deleteItem(int index) {
    final item = items[index];
    final fullPath = '$currentPath/${item["title"]}';

    if (item["type"] == "file") {
      final file = File('${appDocDirectory.path}/$fullPath');
      if (file.existsSync()) file.deleteSync();
    }

    setState(() {
      items.removeAt(index);
      _sortItems();
      filteredItems = items;
    });
    _saveItems();
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: Icon(Icons.folder),
            title: Text('Buat Folder'),
            onTap: () {
              Navigator.pop(context);
              _showInputDialog('folder');
            },
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file),
            title: Text('Buat File'),
            onTap: () {
              Navigator.pop(context);
              _showInputDialog('file');
            },
          ),
        ],
      ),
    );
  }

  void _showInputDialog(String type) {
    TextEditingController controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Masukkan nama ${type == 'folder' ? "folder" : "file"}'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: 'Nama'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () {
              String name = controller.text.trim();
              if (type == 'file' && !_isValidExtension(name)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Format file tidak didukung!')),
                );
                return;
              }
              if (name.isNotEmpty) {
                _addItem(name, type);
              }
              Navigator.pop(context);
            },
            child: Text('Simpan'),
          ),
        ],
      ),
    );
  }

  bool _isValidExtension(String filename) {
    String ext = filename.contains('.')
        ? filename.substring(filename.lastIndexOf('.')).toLowerCase()
        : '';
    return allowedExtensions.contains(ext);
  }

  void _openFolder(Map<String, dynamic> folder) {
    final folderPath = '$currentPath/${folder["title"]}';
    final folderDibuka = '${folder["title"]}';

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return XcodeEditPage(
            currentItems: folder["children"],
            currentPath: folderPath,
            folderDibuka: folderDibuka,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          // Slide transition
          const begin = Offset(1.0, 0.0); // Start from the right
          const end = Offset.zero;
          const curve = Curves.easeInOut;

          var tween =
              Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
          var offsetAnimation = animation.drive(tween);

          return SlideTransition(position: offsetAnimation, child: child);
        },
      ),
    ).then((_) => _saveItems());
  }

  void _openFile(Map<String, dynamic> fileItem) async {
  final filePath = '${appDocDirectory.path}/$currentPath/${fileItem["title"]}';
  final file = File(filePath);

  if (await file.exists()) {
    final content = await file.readAsString();

    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => EditFilePage(
          fileName: fileItem["title"],
          filePath: filePath,
          initialContent: content,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(1.0, 0.0); // Dari kanan ke kiri
          const end = Offset.zero;
          const curve = Curves.ease;

          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
      ),
    ).then((value) {
      setState(() {});
    });
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File tidak ditemukan')),
    );
  }
}


  String _generateFolderSubtitle(List<dynamic> children) {
    List<String> fileNames = children
        .where((child) => child["type"] == "file")
        .map<String>((file) => file["title"] as String)
        .toList();

    if (fileNames.isEmpty) {
      return "Folder kosong";
    }

    String preview = fileNames.take(3).join(', ');
    if (fileNames.length > 3) {
      preview += ", ...";
    }

    return "File ${fileNames.length} - $preview";
  }

  Future<String> _getFileSize(String fileName) async {
    final fullPath = '$currentPath/$fileName';
    final file = File('${appDocDirectory.path}/$fullPath');
    if (await file.exists()) {
      final bytes = await file.length();
      return "${(bytes / 1024).ceil()} KB";
    }
    return "0 KB";
  }

  void _filterItems() {
    final query = searchController.text.toLowerCase();
    setState(() {
      filteredItems = items.where((item) {
        return item['title'].toLowerCase().contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    searchController.removeListener(_filterItems);
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('$currentPath'),
        backgroundColor: Color(0xFF0D47A1),
        foregroundColor: Colors.white,
      ),
      backgroundColor: Colors.grey[100],
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: TextField(
              controller: searchController,
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Cari file atau folder...',
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: filteredItems.isEmpty
                ? Center(child: Text('Tidak ada file atau folder ditemukan.'))
                : ListView.builder(
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      final isFolder = item["type"] == "folder";
                      final children = item["children"];

                      return FutureBuilder<String>(
                        future: isFolder
                            ? Future.value("")
                            : _getFileSize(item["title"]),
                        builder: (context, snapshot) {
                          String subtitle = "";
                          if (isFolder) {
                            subtitle = _generateFolderSubtitle(children ?? []);
                          } else {
                            subtitle = "${snapshot.data ?? '...'}";
                          }

                          return Card(
                            margin: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: Icon(
                                isFolder
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                                color: isFolder ? Colors.orange : Colors.grey,
                              ),
                              title: Text(item["title"]),
                              subtitle: Text(subtitle),
                              trailing: PopupMenuButton(
                                onSelected: (value) {
                                  if (value == 'hapus') {
                                    _deleteItem(index);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'hapus',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Hapus'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                if (isFolder) {
                                  _openFolder(item);
                                } else {
                                  _openFile(item);
                                }
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.blueGrey,
        onPressed: _showAddOptions,
        child: Icon(Icons.add),
      ),
    );
  }
}
