import 'package:fyp2/shared/localization/app_language.dart';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'chat_service.dart';

class ChatPhoto extends StatefulWidget {
  final String path;
  final ChatService service;
  final VoidCallback? onOpen;
  const ChatPhoto({
    super.key,
    required this.path,
    required this.service,
    this.onOpen,
  });
  @override
  State<ChatPhoto> createState() => _ChatPhotoState();
}

class _ChatPhotoState extends State<ChatPhoto> {
  late Future<Uint8List> _bytes = widget.service.photo(widget.path);
  @override
  Widget build(BuildContext context) { AppLanguage.watch(context); return  FutureBuilder<Uint8List>(
    future: _bytes,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return TextButton.icon(
          onPressed: () =>
              setState(() => _bytes = widget.service.photo(widget.path)),
          icon: const Icon(Icons.refresh),
          label:  Text(tr('Reload photo')),
        );
      }
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 200,
          height: 150,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Semantics(
        label: tr('Photo attachment. Tap to enlarge.'),
        button: true,
        child: InkWell(
          onTap:
              widget.onOpen ??
              () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatPhotoGallery(
                    paths: [widget.path],
                    initialPath: widget.path,
                    service: widget.service,
                  ),
                ),
              ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(
              snapshot.data!,
              width: 240,
              height: 180,
              fit: BoxFit.cover,
              cacheWidth: 720,
              errorBuilder: (_, _, _) =>  SizedBox(
                width: 200,
                height: 120,
                child: Center(child: Text(tr('Unsupported photo'))),
              ),
            ),
          ),
        ),
      );
    },
  ); }
}

/// Only visible conversation attachments are supplied; downloads keep Storage RLS.
class ChatPhotoGallery extends StatefulWidget {
  final List<String> paths;
  final String initialPath;
  final ChatService service;
  final Future<List<String>> Function()? loadEarlier;
  const ChatPhotoGallery({
    super.key,
    required this.paths,
    required this.initialPath,
    required this.service,
    this.loadEarlier,
  });
  @override
  State<ChatPhotoGallery> createState() => _ChatPhotoGalleryState();
}

class _ChatPhotoGalleryState extends State<ChatPhotoGallery> {
  late List<String> _paths = List.of(widget.paths);
  late int _index = _paths
      .indexOf(widget.initialPath)
      .clamp(0, _paths.length - 1);
  late final PageController _pages = PageController(initialPage: _index);
  final Map<String, Future<Uint8List>> _downloads = {};
  bool _zoomed = false, _loading = false, _olderDone = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    if (_index == 0) _earlier();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _earlier() async {
    if (_loading || _olderDone || widget.loadEarlier == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final earlier = await widget.loadEarlier!();
      if (!mounted) return;
      final added = earlier.where((p) => !_paths.contains(p)).toList();
      setState(() {
        _olderDone = added.isEmpty;
        _paths = [...added, ..._paths];
        _index += added.length;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients) _pages.jumpToPage(_index);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load earlier photos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _move(int delta) {
    final next = _index + delta;
    if (next < 0 || next >= _paths.length) return;
    _pages.animateToPage(
      next,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) { AppLanguage.watch(context); return  Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      foregroundColor: Colors.white,
      title: Text(tr('Photo ${_index + 1} of ${_paths.length}')),
    ),
    body: Column(
      children: [
        if (_loading) const LinearProgressIndicator(),
        if (_error != null)
          TextButton(onPressed: _earlier, child: Text(tr('$_error Retry'))),
        Expanded(
          child: PageView.builder(
            controller: _pages,
            physics: _zoomed
                ? const NeverScrollableScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: _paths.length,
            onPageChanged: (index) {
              setState(() {
                _index = index;
                _zoomed = false;
                final nearby = _paths
                    .skip(index > 0 ? index - 1 : 0)
                    .take(index > 0 ? 3 : 2)
                    .toSet();
                _downloads.removeWhere((path, _) => !nearby.contains(path));
              });
              if (index == 0) _earlier();
            },
            itemBuilder: (context, index) {
              final path = _paths[index];
              return FutureBuilder<Uint8List>(
                future: _downloads.putIfAbsent(
                  path,
                  () => widget.service.photo(path),
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: TextButton.icon(
                        onPressed: () => setState(() {
                          _downloads[path] = widget.service.photo(path);
                        }),
                        icon: const Icon(Icons.refresh),
                        label:  Text(tr('Retry photo')),
                      ),
                    );
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _ZoomPhoto(
                    key: ValueKey('$path-${index == _index}'),
                    bytes: snapshot.data!,
                    onZoom: (zoom) {
                      if (index == _index && zoom != _zoomed) {
                        setState(() => _zoomed = zoom);
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: trOrNull('Previous photo'),
                onPressed: _index > 0 ? () => _move(-1) : null,
                color: Colors.white,
                disabledColor: Colors.white24,
                icon: const Icon(Icons.chevron_left),
              ),
              Flexible(
                child: Text(
                  tr(_zoomed ? 'Pinch to zoom out, then swipe' : 'Swipe to browse · Pinch to zoom'),
                  style: const TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: trOrNull('Next photo'),
                onPressed: _index < _paths.length - 1 ? () => _move(1) : null,
                color: Colors.white,
                disabledColor: Colors.white24,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    ),
  ); }
}

class _ZoomPhoto extends StatefulWidget {
  final Uint8List bytes;
  final ValueChanged<bool> onZoom;
  const _ZoomPhoto({super.key, required this.bytes, required this.onZoom});
  @override
  State<_ZoomPhoto> createState() => _ZoomPhotoState();
}

class _ZoomPhotoState extends State<_ZoomPhoto> {
  final _transform = TransformationController();
  bool _zoomed = false;
  @override
  void initState() {
    super.initState();
    _transform.addListener(() {
      final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
      if (zoomed != _zoomed) {
        setState(() => _zoomed = zoomed);
        widget.onZoom(zoomed);
      }
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) { AppLanguage.watch(context); return  SizedBox.expand(
    child: InteractiveViewer(
      panEnabled: _zoomed,
      transformationController: _transform,
      minScale: 1,
      maxScale: 4,
      onInteractionEnd: (_) =>
          widget.onZoom(_transform.value.getMaxScaleOnAxis() > 1.01),
      child: SizedBox.expand(
        child: Image.memory(
          widget.bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) =>  Text(
            tr('Photo unavailable'),
            style: TextStyle(color: Colors.white),
          ),
        ),
      ),
    ),
  ); }
}
