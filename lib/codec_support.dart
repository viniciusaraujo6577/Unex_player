import 'core.dart';
import 'native_bridge.dart';

enum PlaybackFailure { none, audioCodec, videoCodec, network, unknown }

/// Detecção de falhas de codec e geração de URLs alternativas.
///
/// O ExoPlayer (usado pelo video_player) já cai automaticamente para decoders
/// de software quando o dispositivo possui algum (AAC, MP3, Opus, Vorbis...).
/// Para formatos sem decoder de software no Android (AC3/E-AC3/DTS/TrueHD em
/// muitas TV Boxes) esta camada: (1) detecta o motivo exato da falha,
/// (2) tenta automaticamente contêineres/formatos alternativos do mesmo
/// conteúdo, e (3) informa o usuário de forma clara.
class CodecSupport {
  CodecSupport._();

  static bool hasAc3 = true;
  static bool hasEac3 = true;
  static bool hasDts = true;

  static final RegExp _heavyAudioName = RegExp(
      r'\b(ac3|e-?ac3|dd5?\.?1|dolby|atmos|dts|truehd)\b',
      caseSensitive: false);

  /// Consulta os decoders nativos do aparelho (rápido, 1x no início).
  static Future<void> probe() async {
    hasAc3 = await NativeBridge.hasHardwareDecoder('audio/ac3');
    hasEac3 = await NativeBridge.hasHardwareDecoder('audio/eac3');
    hasDts = await NativeBridge.hasHardwareDecoder('audio/vnd.dts');
  }

  static bool likelyNeedsUnsupportedAudio(StreamItem item) {
    if (item.type == ContentType.live) return false;
    if (!_heavyAudioName.hasMatch(item.name)) return false;
    return !(hasAc3 && hasEac3 && hasDts);
  }

  static PlaybackFailure classify(String? description) {
    if (description == null || description.isEmpty) {
      return PlaybackFailure.unknown;
    }
    final d = description.toLowerCase();
    if (d.contains('audio/') ||
        d.contains('audiorenderer') ||
        d.contains('audiosink') ||
        d.contains('audiotrack') ||
        d.contains('ac3') ||
        d.contains('eac3') ||
        d.contains('truehd')) {
      return PlaybackFailure.audioCodec;
    }
    if (d.contains('video/') ||
        d.contains('videorenderer') ||
        d.contains('hevc') ||
        d.contains('decoder init failed') ||
        d.contains('mediacodec')) {
      return PlaybackFailure.videoCodec;
    }
    if (d.contains('source error') ||
        d.contains('httpdatasource') ||
        d.contains('unable to connect') ||
        d.contains('timeout') ||
        d.contains('unknownhost')) {
      return PlaybackFailure.network;
    }
    return PlaybackFailure.unknown;
  }

  static String messageFor(PlaybackFailure f) {
    switch (f) {
      case PlaybackFailure.audioCodec:
        return 'O áudio deste conteúdo (ex.: Dolby AC3/DTS) não é suportado '
            'por este aparelho. Tente outra versão/dublagem do título.';
      case PlaybackFailure.videoCodec:
        return 'O vídeo deste conteúdo usa um formato (ex.: HEVC/4K) que o '
            'aparelho não consegue decodificar. Tente a versão HD/SD.';
      case PlaybackFailure.network:
        return 'Falha de conexão com o servidor. Verifique sua internet.';
      default:
        return 'Transmissão indisponível no momento.';
    }
  }

  /// Lista ordenada de URLs para tentar. O índice 0 é sempre a original.
  static List<String> variants(StreamItem item) {
    final url = item.url;
    final out = <String>[url];
    final m = RegExp(r'^(.*)\.(ts|m3u8|mp4|mkv|avi)(\?.*)?$',
            caseSensitive: false)
        .firstMatch(url);
    if (m == null) return out;

    final base = m.group(1)!;
    final ext = m.group(2)!.toLowerCase();
    final query = m.group(3) ?? '';

    void add(String e) {
      final u = '$base.$e$query';
      if (!out.contains(u)) out.add(u);
    }

    if (item.type == ContentType.live) {
      add(ext == 'ts' ? 'm3u8' : 'ts');
    } else {
      // VOD: painéis Xtream costumam servir o mesmo arquivo em outro
      // contêiner e, com HLS, às vezes com áudio convertido para AAC.
      if (ext != 'm3u8') add('m3u8');
      if (ext != 'mp4') add('mp4');
      if (ext != 'mkv') add('mkv');
    }
    return out;
  }
}
