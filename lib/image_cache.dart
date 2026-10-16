import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'native_bridge.dart';

/// Perfil de memória escolhido conforme a RAM do aparelho.
class ImageMemoryProfile {
  final int maxBytes;
  final int maxImages;
  final int maxDecodePx; // maior lado decodificado
  final int maxDiskObjects;
  const ImageMemoryProfile(
      this.maxBytes, this.maxImages, this.maxDecodePx, this.maxDiskObjects);

  static const low = ImageMemoryProfile(16 * 1024 * 1024, 50, 240, 800);
  static const medium = ImageMemoryProfile(40 * 1024 * 1024, 100, 360, 1500);
  static const high = ImageMemoryProfile(96 * 1024 * 1024, 200, 480, 3000);
}

class ImageMemory {
  ImageMemory._();

  static ImageMemoryProfile profile = ImageMemoryProfile.medium;
  static CacheManager? _manager;

  /// Chamar uma única vez no início do app (antes do runApp).
  static Future<void> configure() async {
    final ramMb = await NativeBridge.totalRamMb();
    if (ramMb <= 1536) {
      profile = ImageMemoryProfile.low;
    } else if (ramMb <= 2560) {
      profile = ImageMemoryProfile.medium;
    } else {
      profile = ImageMemoryProfile.high;
    }

    final cache = PaintingBinding.instance.imageCache;
    cache.maximumSizeBytes = profile.maxBytes;
    cache.maximumSize = profile.maxImages;

    _manager = CacheManager(
      Config(
        'unex_images',
        stalePeriod: const Duration(days: 14),
        maxNrOfCacheObjects: profile.maxDiskObjects,
      ),
    );
  }

  static CacheManager get manager =>
      _manager ??
      (_manager = CacheManager(Config('unex_images',
          stalePeriod: const Duration(days: 14), maxNrOfCacheObjects: 1500)));

  /// Limpa o cache de RAM (ex.: ao receber aviso de pouca memória).
  static void trimMemory() {
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}

/// Imagem de rede com:
///  - cache em disco (não baixa o mesmo logotipo toda hora);
///  - decodificação reduzida (cacheWidth) => poucos MB de RAM por imagem;
///  - fila de download limitada para não saturar TV Box fraca;
///  - placeholder/erro leves.
class AppImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final Widget Function()? placeholder;
  final int? decodeWidth;

  const AppImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.decodeWidth,
  });

  @override
  State<AppImage> createState() => _AppImageState();
}

class _AppImageState extends State<AppImage> {
  File? _file;
  bool _failed = false;
  static int _active = 0;
  static const int _maxParallel = 4;
  static final List<Completer<void>> _queue = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant AppImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _file = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _acquire() async {
    if (_active < _maxParallel) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _queue.add(c);
    await c.future;
  }

  void _release() {
    if (_queue.isNotEmpty) {
      _queue.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    if (url.isEmpty || !(url.startsWith('http://') || url.startsWith('https://'))) {
      if (mounted) setState(() => _failed = true);
      return;
    }
    try {
      final cached = await ImageMemory.manager.getFileFromCache(url);
      if (cached != null && cached.validTill.isAfter(DateTime.now())) {
        if (mounted && widget.url == url) setState(() => _file = cached.file);
        return;
      }
      await _acquire();
      try {
        final file = await ImageMemory.manager
            .getSingleFile(url)
            .timeout(const Duration(seconds: 12));
        if (mounted && widget.url == url) setState(() => _file = file);
      } finally {
        _release();
      }
    } catch (_) {
      if (mounted && widget.url == url) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final holder = widget.placeholder?.call() ??
        const ColoredBox(color: Color(0xFF101420));
    if (_failed) return holder;
    final f = _file;
    if (f == null) return holder;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cap = ImageMemory.profile.maxDecodePx;
    final target = widget.decodeWidth ?? cap;
    final px = (target * (dpr > 2 ? 1.5 : dpr)).round().clamp(64, cap);

    return Image.file(
      f,
      fit: widget.fit,
      cacheWidth: px,
      filterQuality: FilterQuality.low,
      gaplessPlayback: true,
      errorBuilder: (_, __, ___) => holder,
    );
  }
}
