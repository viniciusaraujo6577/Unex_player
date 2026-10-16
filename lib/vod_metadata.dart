import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'core.dart';
import 'image_cache.dart';

// =============================================================================
// MODELO
// =============================================================================
class VodMetadata {
  final String plot;
  final String cast;
  final String director;
  final String genre;
  final String releaseDate;
  final String year;
  final double? rating; // 0-10
  final String duration;
  final String age;
  final String country;
  final String cover;
  final String backdrop;

  const VodMetadata({
    this.plot = '',
    this.cast = '',
    this.director = '',
    this.genre = '',
    this.releaseDate = '',
    this.year = '',
    this.rating,
    this.duration = '',
    this.age = '',
    this.country = '',
    this.cover = '',
    this.backdrop = '',
  });

  bool get isEmpty =>
      plot.isEmpty &&
      cast.isEmpty &&
      director.isEmpty &&
      genre.isEmpty &&
      year.isEmpty &&
      rating == null &&
      duration.isEmpty;

  /// Usa este metadado e completa os campos vazios com os de [fb]
  /// (ex.: episódio sem elenco usa o elenco da série).
  VodMetadata mergedWith(VodMetadata fb) => VodMetadata(
        plot: plot.isNotEmpty ? plot : fb.plot,
        cast: cast.isNotEmpty ? cast : fb.cast,
        director: director.isNotEmpty ? director : fb.director,
        genre: genre.isNotEmpty ? genre : fb.genre,
        releaseDate: releaseDate.isNotEmpty ? releaseDate : fb.releaseDate,
        year: year.isNotEmpty ? year : fb.year,
        rating: rating ?? fb.rating,
        duration: duration.isNotEmpty ? duration : fb.duration,
        age: age.isNotEmpty ? age : fb.age,
        country: country.isNotEmpty ? country : fb.country,
        cover: cover.isNotEmpty ? cover : fb.cover,
        backdrop: backdrop.isNotEmpty ? backdrop : fb.backdrop,
      );

  Map<String, dynamic> toJson() => {
        'plot': plot,
        'cast': cast,
        'director': director,
        'genre': genre,
        'releaseDate': releaseDate,
        'year': year,
        'rating': rating,
        'duration': duration,
        'age': age,
        'country': country,
        'cover': cover,
        'backdrop': backdrop,
      };

  factory VodMetadata.fromJson(Map<String, dynamic> j) => VodMetadata(
        plot: j['plot']?.toString() ?? '',
        cast: j['cast']?.toString() ?? '',
        director: j['director']?.toString() ?? '',
        genre: j['genre']?.toString() ?? '',
        releaseDate: j['releaseDate']?.toString() ?? '',
        year: j['year']?.toString() ?? '',
        rating: (j['rating'] as num?)?.toDouble(),
        duration: j['duration']?.toString() ?? '',
        age: j['age']?.toString() ?? '',
        country: j['country']?.toString() ?? '',
        cover: j['cover']?.toString() ?? '',
        backdrop: j['backdrop']?.toString() ?? '',
      );

  /// Constrói a partir do bloco "info" de get_vod_info / get_series_info.
  /// Painéis Xtream variam os nomes dos campos, por isso há várias chaves.
  factory VodMetadata.fromXtreamInfo(Map info) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = info[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty && s.toLowerCase() != 'null') return s;
      }
      return '';
    }

    final release =
        pick(['releasedate', 'releaseDate', 'release_date', 'year']);
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(release);

    double? rating;
    final r5 = double.tryParse(pick(['rating_5based']));
    final r10 = double.tryParse(pick(['rating', 'rating_imdb', 'rating_tmdb']));
    if (r10 != null && r10 > 0) {
      rating = r10 > 10 ? 10 : r10;
    } else if (r5 != null && r5 > 0) {
      rating = r5 * 2;
    }

    String duration = pick(['duration', 'episode_run_time']);
    if (duration.isEmpty) {
      final secs = int.tryParse(pick(['duration_secs']));
      if (secs != null && secs > 0) {
        final h = secs ~/ 3600;
        final m = (secs % 3600) ~/ 60;
        duration = h > 0 ? '${h}h ${m.toString().padLeft(2, '0')}min' : '${m}min';
      }
    } else if (int.tryParse(duration) != null) {
      duration = '${duration}min';
    }

    String backdrop = pick(['backdrop']);
    if (backdrop.isEmpty && info['backdrop_path'] is List) {
      final l = info['backdrop_path'] as List;
      if (l.isNotEmpty) backdrop = l.first.toString();
    }

    return VodMetadata(
      plot: pick(['plot', 'description', 'overview']),
      cast: pick(['cast', 'actors']),
      director: pick(['director']),
      genre: pick(['genre']),
      releaseDate: release,
      year: yearMatch?.group(0) ?? '',
      rating: rating,
      duration: duration,
      age: pick(['age', 'mpaa_rating']),
      country: pick(['country']),
      cover: pick(['movie_image', 'cover', 'cover_big']),
      backdrop: backdrop,
    );
  }
}

class SeriesMetadata {
  final VodMetadata info;
  final Map<String, VodMetadata> episodes; // chave = id do episódio (streamId)
  const SeriesMetadata({required this.info, required this.episodes});
}

// =============================================================================
// SERVIÇO (com cache em memória + disco)
// =============================================================================
class MetadataService {
  MetadataService._();

  static const _diskFile = 'unex_meta_v9.json';
  static const _indexFile = 'unex_series_index_v9.json';
  static const _maxDiskEntries = 300;

  static final Map<String, Map<String, dynamic>> _disk = {};
  static bool _diskLoaded = false;
  static Map<String, int>? _seriesIndex;

  static Future<void> _ensureDiskLoaded() async {
    if (_diskLoaded) return;
    _diskLoaded = true;
    try {
      final raw = await AppStorage.readJsonFile(_diskFile);
      if (raw is Map) {
        raw.forEach((k, v) {
          if (v is Map) _disk[k.toString()] = v.cast<String, dynamic>();
        });
      }
    } catch (_) {}
  }

  static void _persist() {
    while (_disk.length > _maxDiskEntries) {
      _disk.remove(_disk.keys.first);
    }
    AppStorage.writeJsonFile(_diskFile, _disk);
  }

  static Future<dynamic> _getJson(String url, {int timeoutSec = 12}) async {
    final res = await http
        .get(Uri.parse(url), headers: kIptvHeaders)
        .timeout(Duration(seconds: timeoutSec));
    if (res.statusCode != 200) return null;
    return jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
  }

  static String _api(String dns, String user, String pass, String action,
          [String extra = '']) =>
      '$dns/player_api.php?username=${Uri.encodeQueryComponent(user)}&password=${Uri.encodeQueryComponent(pass)}&action=$action$extra';

  // ------------------------------- FILMES ------------------------------------
  static Future<VodMetadata?> forMovie({
    required StreamItem item,
    required String dns,
    required String user,
    required String pass,
  }) async {
    if (item.streamId.isEmpty || dns.isEmpty) return null;
    await _ensureDiskLoaded();
    final key = 'm_${item.streamId}';
    final cached = _disk[key];
    if (cached != null) return VodMetadata.fromJson(cached);

    try {
      final data = await _getJson(
          _api(dns, user, pass, 'get_vod_info', '&vod_id=${item.streamId}'));
      if (data is Map && data['info'] is Map) {
        final meta = VodMetadata.fromXtreamInfo(data['info'] as Map);
        if (!meta.isEmpty) {
          _disk[key] = meta.toJson();
          _persist();
          return meta;
        }
      }
    } catch (_) {}
    return null;
  }

  // ------------------------------- SÉRIES ------------------------------------
  static String normalizeTitle(String s) {
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'\(.*?\)|\[.*?\]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9à-ú]+'), '');
  }

  // Executa em isolate: lista de séries pode ter vários MB.
  static Map<String, int> _buildIndex(String body) {
    final out = <String, int>{};
    final data = jsonDecode(body);
    if (data is List) {
      for (final e in data) {
        if (e is Map) {
          final id = int.tryParse(e['series_id']?.toString() ?? '');
          final name = e['name']?.toString() ?? '';
          if (id != null && name.isNotEmpty) {
            out.putIfAbsent(normalizeTitle(name), () => id);
          }
        }
      }
    }
    return out;
  }

  static Future<Map<String, int>> _loadSeriesIndex(
      String dns, String user, String pass) async {
    if (_seriesIndex != null) return _seriesIndex!;

    try {
      final raw = await AppStorage.readJsonFile(_indexFile);
      if (raw is Map) {
        final savedAt = (raw['savedAt'] as int?) ?? 0;
        final fresh = DateTime.now().millisecondsSinceEpoch - savedAt <
            const Duration(hours: 24).inMilliseconds;
        if (fresh && raw['map'] is Map) {
          _seriesIndex = (raw['map'] as Map)
              .map((k, v) => MapEntry(k.toString(), (v as num).toInt()));
          return _seriesIndex!;
        }
      }
    } catch (_) {}

    try {
      final res = await http
          .get(Uri.parse(_api(dns, user, pass, 'get_series')),
              headers: kIptvHeaders)
          .timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes, allowMalformed: true);
        final idx = await compute(_buildIndex, body);
        _seriesIndex = idx;
        AppStorage.writeJsonFile(_indexFile, {
          'savedAt': DateTime.now().millisecondsSinceEpoch,
          'map': idx,
        });
        return idx;
      }
    } catch (_) {}
    return {};
  }

  static Future<SeriesMetadata?> forSeries({
    required SeriesGroup series,
    required String dns,
    required String user,
    required String pass,
  }) async {
    if (dns.isEmpty) return null;
    await _ensureDiskLoaded();
    final key = 's_${series.id}';
    final cached = _disk[key];
    if (cached != null) {
      try {
        final info =
            VodMetadata.fromJson((cached['info'] as Map).cast<String, dynamic>());
        final eps = <String, VodMetadata>{};
        (cached['episodes'] as Map?)?.forEach((k, v) {
          eps[k.toString()] =
              VodMetadata.fromJson((v as Map).cast<String, dynamic>());
        });
        return SeriesMetadata(info: info, episodes: eps);
      } catch (_) {}
    }

    try {
      final index = await _loadSeriesIndex(dns, user, pass);
      if (index.isEmpty) return null;

      final target = normalizeTitle(series.title);
      int? seriesId = index[target];
      if (seriesId == null && target.length >= 4) {
        for (final e in index.entries) {
          if (e.key.startsWith(target) || target.startsWith(e.key)) {
            seriesId = e.value;
            break;
          }
        }
      }
      if (seriesId == null) return null;

      final data = await _getJson(
          _api(dns, user, pass, 'get_series_info', '&series_id=$seriesId'),
          timeoutSec: 15);
      if (data is! Map) return null;

      final info = data['info'] is Map
          ? VodMetadata.fromXtreamInfo(data['info'] as Map)
          : const VodMetadata();

      final eps = <String, VodMetadata>{};
      final rawEps = data['episodes'];
      void readEpisode(dynamic e) {
        if (e is Map) {
          final id = e['id']?.toString();
          final epInfo = e['info'];
          if (id != null && epInfo is Map) {
            final m = VodMetadata.fromXtreamInfo(epInfo);
            if (!m.isEmpty) eps[id] = m;
          }
        }
      }

      if (rawEps is Map) {
        for (final season in rawEps.values) {
          if (season is List) season.forEach(readEpisode);
        }
      } else if (rawEps is List) {
        for (final season in rawEps) {
          if (season is List) {
            season.forEach(readEpisode);
          } else {
            readEpisode(season);
          }
        }
      }

      final result = SeriesMetadata(info: info, episodes: eps);
      if (!info.isEmpty || eps.isNotEmpty) {
        _disk[key] = {
          'info': info.toJson(),
          'episodes': eps.map((k, v) => MapEntry(k, v.toJson())),
        };
        _persist();
      }
      return result;
    } catch (_) {
      return null;
    }
  }
}

// =============================================================================
// TELA DE DETALHES (ANTES DO PLAY) - FILMES E EPISÓDIOS
// =============================================================================
class VodDetailsScreen extends StatefulWidget {
  final StreamItem item;
  final DeviceMode deviceMode;
  final SeriesGroup? series;
  final Future<VodMetadata?> metadataFuture;
  final VodProgressEntry? progress;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;

  /// Chamado ao apertar assistir. [start] = posição inicial escolhida.
  final void Function(Duration? start) onPlay;

  const VodDetailsScreen({
    super.key,
    required this.item,
    required this.deviceMode,
    required this.metadataFuture,
    required this.onPlay,
    required this.onToggleFavorite,
    required this.isFavorite,
    this.series,
    this.progress,
  });

  @override
  State<VodDetailsScreen> createState() => _VodDetailsScreenState();
}

class _VodDetailsScreenState extends State<VodDetailsScreen> {
  late bool _fav = widget.isFavorite;

  String get _titleFromName {
    if (widget.series != null) {
      return '${widget.series!.title}  •  T${widget.item.seasonNumber}:E${widget.item.episodeNumber}';
    }
    return widget.item.cleanName.isNotEmpty
        ? widget.item.cleanName
        : widget.item.name;
  }

  String? get _yearFromName {
    final m = RegExp(r'\b(19|20)\d{2}\b').firstMatch(widget.item.name);
    return m?.group(0);
  }

  Widget _chip(String text, {IconData? icon, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color ?? const Color(0xFF00E5FF)),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _techRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF00E5FF),
                    fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 12, color: Colors.white70, height: 1.35)),
          ),
        ],
      ),
    );
  }

  Widget _button({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = false,
    bool autofocus = false,
    Color? iconColor,
  }) {
    return TVFocusableItem(
      autofocus: autofocus,
      autoScroll: true,
      onSelect: onTap,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.05 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    colors: [Color(0xFF00E5FF), Color(0xFF2979FF)])
                : null,
            color: primary ? null : const Color(0xFF151924),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: focused ? Colors.white : Colors.white24,
              width: focused ? 2.2 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 20,
                  color: primary ? Colors.black : (iconColor ?? Colors.white)),
              const SizedBox(width: 7),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: primary ? Colors.black : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final prog = widget.progress;

    return Scaffold(
      backgroundColor: const Color(0xFF08090E),
      body: SafeArea(
        child: FutureBuilder<VodMetadata?>(
          future: widget.metadataFuture,
          builder: (context, snap) {
            final meta = snap.data;
            final loading = snap.connectionState != ConnectionState.done;
            final poster = (meta?.cover.isNotEmpty ?? false)
                ? meta!.cover
                : (widget.series?.logo.isNotEmpty ?? false) && item.logo.isEmpty
                    ? widget.series!.logo
                    : item.logo;
            final backdrop = meta?.backdrop ?? '';

            final year = (meta?.year.isNotEmpty ?? false)
                ? meta!.year
                : (_yearFromName ?? '');

            final posterWidget = ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                width: 170,
                height: 250,
                color: const Color(0xFF101420),
                child: AppImage(
                  url: poster,
                  decodeWidth: 340,
                  placeholder: () => const Center(
                    child: Icon(Icons.movie_filter_rounded,
                        color: Color(0xFF00E5FF), size: 46),
                  ),
                ),
              ),
            );

            final infoColumn = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_titleFromName,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w900, height: 1.15)),
                if (widget.series != null && item.name.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: Colors.white60)),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (year.isNotEmpty) _chip(year, icon: Icons.calendar_today_rounded),
                    if (meta?.rating != null)
                      _chip(meta!.rating!.toStringAsFixed(1),
                          icon: Icons.star_rounded, color: Colors.amber),
                    if ((meta?.duration ?? '').isNotEmpty)
                      _chip(meta!.duration, icon: Icons.schedule_rounded),
                    if ((meta?.age ?? '').isNotEmpty)
                      _chip('${meta!.age}+', icon: Icons.shield_outlined),
                    _chip(item.qualityTag, icon: Icons.high_quality_rounded),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (prog != null && prog.progress < 0.96) ...[
                      _button(
                        label: 'Continuar de ${prog.formattedPosition}',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        autofocus: true,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onPlay(Duration(seconds: prog.positionSeconds));
                        },
                      ),
                      _button(
                        label: 'Do início',
                        icon: Icons.replay_rounded,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onPlay(Duration.zero);
                        },
                      ),
                    ] else
                      _button(
                        label: 'Assistir',
                        icon: Icons.play_arrow_rounded,
                        primary: true,
                        autofocus: true,
                        onTap: () {
                          Navigator.pop(context);
                          widget.onPlay(null);
                        },
                      ),
                    _button(
                      label: _fav ? 'Favorito' : 'Favoritar',
                      icon: _fav ? Icons.star_rounded : Icons.star_border_rounded,
                      iconColor: _fav ? Colors.amber : Colors.white,
                      onTap: () {
                        setState(() => _fav = !_fav);
                        widget.onToggleFavorite();
                      },
                    ),
                    _button(
                      label: 'Voltar',
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                const Text('SINOPSE',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                        color: Colors.white54)),
                const SizedBox(height: 6),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF00E5FF)),
                    ),
                  )
                else
                  TVFocusableItem(
                    autoScroll: true,
                    onSelect: () {},
                    builder: (context, focused) => Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: focused
                              ? const Color(0xFF00E5FF).withOpacity(0.6)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        (meta?.plot.isNotEmpty ?? false)
                            ? meta!.plot
                            : 'Sinopse não disponível para este título.',
                        style: const TextStyle(
                            fontSize: 13.5, color: Colors.white70, height: 1.5),
                      ),
                    ),
                  ),
                const SizedBox(height: 18),
                if (meta != null &&
                    (meta.genre.isNotEmpty ||
                        meta.director.isNotEmpty ||
                        meta.cast.isNotEmpty ||
                        meta.country.isNotEmpty ||
                        meta.releaseDate.isNotEmpty)) ...[
                  const Text('FICHA TÉCNICA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Colors.white54)),
                  const SizedBox(height: 10),
                  _techRow('Gênero', meta.genre),
                  _techRow('Direção', meta.director),
                  _techRow('Elenco', meta.cast),
                  _techRow('País', meta.country),
                  _techRow('Lançamento', meta.releaseDate),
                  _techRow('Categoria', item.group),
                  _techRow('Qualidade', item.qualityTag),
                ] else if (!loading) ...[
                  const Text('FICHA TÉCNICA',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Colors.white54)),
                  const SizedBox(height: 10),
                  _techRow('Categoria', item.group),
                  _techRow('Qualidade', item.qualityTag),
                ],
                const SizedBox(height: 24),
              ],
            );

            return Stack(
              fit: StackFit.expand,
              children: [
                if (backdrop.isNotEmpty)
                  Opacity(
                    opacity: 0.22,
                    child: AppImage(url: backdrop, decodeWidth: 720),
                  ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF08090E).withOpacity(0.55),
                        const Color(0xFF08090E),
                      ],
                    ),
                  ),
                ),
                LayoutBuilder(
                  builder: (context, c) {
                    final wide = c.maxWidth >= 640;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                posterWidget,
                                const SizedBox(width: 24),
                                Expanded(child: infoColumn),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Center(child: posterWidget),
                                const SizedBox(height: 18),
                                infoColumn,
                              ],
                            ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
