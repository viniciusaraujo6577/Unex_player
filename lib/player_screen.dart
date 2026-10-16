import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'core.dart';
import 'native_bridge.dart';

class SmartAdaptivePlayerScreen extends StatefulWidget {
  final DeviceMode deviceMode;
  final StreamItem initialItem;
  final List<StreamItem> playlist;
  final List<StreamItem> liveChannelsPool;
  final double measuredSpeedMbps;
  final Duration? initialStartPosition;
  final Set<String> favoriteIds;
  final ValueChanged<StreamItem> onToggleFavorite;
  final void Function(StreamItem item) onMinimizeToPip;

  const SmartAdaptivePlayerScreen({
    super.key,
    required this.deviceMode,
    required this.initialItem,
    required this.playlist,
    required this.liveChannelsPool,
    required this.measuredSpeedMbps,
    this.initialStartPosition,
    required this.favoriteIds,
    required this.onToggleFavorite,
    required this.onMinimizeToPip,
  });

  @override
  State<SmartAdaptivePlayerScreen> createState() =>
      _SmartAdaptivePlayerScreenState();
}

class _SmartAdaptivePlayerScreenState extends State<SmartAdaptivePlayerScreen> {
  final SharedStreamEngine _engine = SharedStreamEngine.instance;
  late StreamItem currentItem;

  bool showOsd = true;
  bool showQuickChannelDrawer = false;
  bool showStartupHint = true;

  int aspectMode = 0;
  final List<String> aspectLabels = ['Original', 'Esticar', '16:9', '4:3'];

  Timer? _hideTimer;
  Timer? _hintTimer;
  Timer? _sleepTimer;
  int? _sleepMinutesRemaining;

  // Próximo Episódio Automático (Séries)
  Timer? _nextEpisodeTimer;
  int? _nextEpisodeCountdown;
  StreamItem? _upcomingEpisodeItem;

  final FocusNode _playPauseFocusNode = FocusNode();

  // ---- Modo celular: gestos + PiP nativo ----
  bool get _isMobile => widget.deviceMode == DeviceMode.mobile;
  bool _pipSupported = false;
  bool _inPip = false;

  // gesto atual: 'brightness' | 'volume' | 'seek' | null
  String? _gestureKind;
  double _gestureValue = 0; // 0..1 (brilho/volume)
  double _gestureStartValue = 0;
  double _gestureAccum = 0; // deslocamento acumulado (px)
  int _seekSteps = 0;
  Timer? _gestureHideTimer;

  void _onPipChanged() {
    if (!mounted) return;
    setState(() => _inPip = NativeBridge.isInPip.value);
  }

  Future<void> _setupMobileFeatures() async {
    NativeBridge.isInPip.addListener(_onPipChanged);
    _pipSupported = await NativeBridge.isPipSupported();
    if (_pipSupported) {
      // Botão Home com o player aberto => vira janela flutuante do sistema
      await NativeBridge.setPipAllowed(true);
    }
    if (mounted) setState(() {});
  }

  void _showGesture(String kind, double value) {
    _gestureHideTimer?.cancel();
    setState(() {
      _gestureKind = kind;
      _gestureValue = value;
    });
    _gestureHideTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _gestureKind = null);
    });
  }

  Future<void> _onVerticalDragStart(DragStartDetails d, double width) async {
    final isLeft = d.localPosition.dx < width / 2;
    _gestureAccum = 0;
    _gestureKind = isLeft ? 'brightness' : 'volume';
    _gestureStartValue = isLeft
        ? await NativeBridge.getBrightness()
        : await NativeBridge.getVolume();
    _gestureValue = _gestureStartValue;
    if (mounted) setState(() {});
  }

  void _onVerticalDragUpdate(DragUpdateDetails d, double height) {
    final kind = _gestureKind;
    if (kind != 'brightness' && kind != 'volume') return;
    _gestureAccum -= d.delta.dy; // arrastar p/ cima aumenta
    final v = (_gestureStartValue + _gestureAccum / (height * 0.75))
        .clamp(0.0, 1.0)
        .toDouble();
    if (kind == 'brightness') {
      NativeBridge.setBrightness(v);
    } else {
      NativeBridge.setVolume(v);
    }
    _showGesture(kind!, v);
  }

  void _onVerticalDragEnd() {
    _gestureHideTimer?.cancel();
    _gestureHideTimer = Timer(const Duration(milliseconds: 600), () {
      if (mounted) setState(() => _gestureKind = null);
    });
  }

  void _onHorizontalDragStart() {
    if (currentItem.type == ContentType.live) return; // ao vivo não tem seek
    _gestureAccum = 0;
    _seekSteps = 0;
    _gestureKind = 'seek';
  }

  void _onHorizontalDragUpdate(DragUpdateDetails d) {
    if (_gestureKind != 'seek') return;
    _gestureAccum += d.delta.dx;
    // a cada ~45 px arrastados = 1 passo de 10 segundos
    final steps = (_gestureAccum / 45).truncate();
    if (steps != _seekSteps) {
      _gestureHideTimer?.cancel();
      setState(() => _seekSteps = steps);
    }
  }

  void _onHorizontalDragEnd() {
    if (_gestureKind != 'seek') return;
    final steps = _seekSteps;
    if (steps != 0) _engine.seekRelative(steps * 10);
    _gestureHideTimer?.cancel();
    _gestureHideTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        setState(() {
          _gestureKind = null;
          _seekSteps = 0;
        });
      }
    });
  }

  Widget _buildGestureIndicator() {
    final kind = _gestureKind;
    if (kind == null) return const SizedBox.shrink();

    IconData icon;
    String label;
    double? bar;
    if (kind == 'seek') {
      final secs = _seekSteps * 10;
      icon = secs >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded;
      label = '${secs >= 0 ? '+' : '−'}${secs.abs()}s';
    } else if (kind == 'brightness') {
      icon = Icons.brightness_6_rounded;
      label = '${(_gestureValue * 100).round()}%';
      bar = _gestureValue;
    } else {
      icon = _gestureValue <= 0.01
          ? Icons.volume_off_rounded
          : _gestureValue < 0.5
              ? Icons.volume_down_rounded
              : Icons.volume_up_rounded;
      label = '${(_gestureValue * 100).round()}%';
      bar = _gestureValue;
    }

    return IgnorePointer(
      child: Center(
        child: Container(
          width: 120,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.78),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: const Color(0xFF00E5FF), size: 32),
              const SizedBox(height: 6),
              Text(label,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w900)),
              if (bar != null) ...[
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: bar,
                    minHeight: 5,
                    backgroundColor: Colors.white24,
                    color: const Color(0xFF00E5FF),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Camada de gestos EXCLUSIVA do celular. Cobre só a área central do vídeo
  /// (deixa topo, rodapé de controles e bordas livres) e fica desligada
  /// quando a gaveta lateral está aberta. Na TV nem é construída.
  Widget _buildGestureLayer() {
    if (!_isMobile || showQuickChannelDrawer) return const SizedBox.shrink();
    return Positioned(
      top: 72,
      bottom: showOsd ? 170 : 0,
      left: 28,
      right: 28,
      child: LayoutBuilder(
        builder: (context, c) => GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragStart: (d) => _onVerticalDragStart(d, c.maxWidth),
          onVerticalDragUpdate: (d) => _onVerticalDragUpdate(d, c.maxHeight),
          onVerticalDragEnd: (_) => _onVerticalDragEnd(),
          onVerticalDragCancel: _onVerticalDragEnd,
          onHorizontalDragStart: (_) => _onHorizontalDragStart(),
          onHorizontalDragUpdate: _onHorizontalDragUpdate,
          onHorizontalDragEnd: (_) => _onHorizontalDragEnd(),
          onHorizontalDragCancel: _onHorizontalDragEnd,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    currentItem = widget.initialItem;
    if (_isMobile) _setupMobileFeatures();

    _engine.onVodEpisodeEnded = _triggerAutoPlayNextEpisode;

    // Mantém o fluxo contínuo sem reiniciar se já estiver tocando na pré-visualização
    _engine.openStream(
      currentItem,
      startPosition: widget.initialStartPosition,
    );

    _resetOsdTimer();

    // Oculta a legenda discreta de ajuda após 3 segundos
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => showStartupHint = false);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && showOsd) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    if (_engine.onVodEpisodeEnded == _triggerAutoPlayNextEpisode) {
      _engine.onVodEpisodeEnded = null;
    }
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _sleepTimer?.cancel();
    _nextEpisodeTimer?.cancel();
    _gestureHideTimer?.cancel();
    _playPauseFocusNode.dispose();
    if (_isMobile) {
      NativeBridge.isInPip.removeListener(_onPipChanged);
      NativeBridge.setPipAllowed(false);
      NativeBridge.resetBrightness();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _cancelAutoPlayNext() {
    _nextEpisodeTimer?.cancel();
    if (_nextEpisodeCountdown != null) {
      setState(() {
        _nextEpisodeCountdown = null;
        _upcomingEpisodeItem = null;
      });
    }
  }

  void _triggerAutoPlayNextEpisode() {
    if (!mounted || currentItem.type != ContentType.series) return;
    if (_nextEpisodeCountdown != null) return;

    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1 || idx + 1 >= widget.playlist.length) return;

    final nextEp = widget.playlist[idx + 1];
    setState(() {
      _upcomingEpisodeItem = nextEp;
      _nextEpisodeCountdown = 5;
    });

    _nextEpisodeTimer?.cancel();
    _nextEpisodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_nextEpisodeCountdown != null && _nextEpisodeCountdown! > 1) {
        setState(() => _nextEpisodeCountdown = _nextEpisodeCountdown! - 1);
      } else {
        timer.cancel();
        final target = _upcomingEpisodeItem;
        setState(() {
          _nextEpisodeCountdown = null;
          _upcomingEpisodeItem = null;
        });
        if (target != null) {
          _switchStream(target);
        }
      }
    });
  }

  void _switchStream(StreamItem item, {bool forceReload = false}) {
    _cancelAutoPlayNext();
    setState(() {
      currentItem = item;
      showOsd = true;
    });
    _engine.openStream(item, forceReload: forceReload);
    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && showOsd) {
        _playPauseFocusNode.requestFocus();
      }
    });
  }

  /// Exibe a interface do player com animação curta de Fade e foca no Play/Pause
  void _revealOsdWithFade() {
    setState(() => showOsd = true);
    _resetOsdTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playPauseFocusNode.requestFocus();
    });
  }

  void _resetOsdTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !showQuickChannelDrawer) {
        setState(() => showOsd = false);
      }
    });
  }

  /// Troca de canal EXCLUSIVAMENTE quando acionada pelos botões de seta na tela ao lado do Play/Pause
  void _stepChannelByButton(int delta) {
    if (widget.playlist.isEmpty) return;
    final idx = widget.playlist.indexWhere((i) => i.id == currentItem.id);
    if (idx == -1) return;
    final next =
        (idx + delta + widget.playlist.length) % widget.playlist.length;
    _switchStream(widget.playlist[next]);
  }

  void _recallPreviousChannel() {
    final prev = _engine.previousChannelItem;
    if (prev != null && prev.id != currentItem.id) {
      _switchStream(prev);
    }
  }

  List<StreamItem> _getQualities() {
    if (currentItem.type != ContentType.live) return [currentItem];
    final target = currentItem.cleanName.toLowerCase();
    final list = widget.liveChannelsPool
        .where((i) => i.cleanName.toLowerCase() == target)
        .take(5)
        .toList();
    return list.isEmpty ? [currentItem] : list;
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _openSleepTimerModal() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.bedtime_rounded, color: Color(0xFF00E5FF)),
            SizedBox(width: 10),
            Text('Timer de Sono (Sleep)', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final mins in [15, 30, 60, 90, 120])
              TVFocusableItem(
                autofocus: mins == 30,
                autoScroll: false,
                onSelect: () {
                  _setSleepTimer(mins);
                  Navigator.pop(ctx);
                },
                builder: (context, isFocused) => Container(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isFocused ? Colors.white10 : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused
                          ? const Color(0xFF00E5FF)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.timer_outlined,
                          size: 18, color: Color(0xFF00E5FF)),
                      const SizedBox(width: 10),
                      Text('Desligar em $mins minutos'),
                    ],
                  ),
                ),
              ),
            if (_sleepMinutesRemaining != null)
              TVFocusableItem(
                autoScroll: false,
                onSelect: () {
                  _sleepTimer?.cancel();
                  setState(() => _sleepMinutesRemaining = null);
                  Navigator.pop(ctx);
                },
                builder: (context, isFocused) => Container(
                  margin: const EdgeInsets.only(top: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isFocused ? Colors.redAccent : Colors.transparent,
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.redAccent),
                      SizedBox(width: 10),
                      Text('Cancelar Timer',
                          style: TextStyle(color: Colors.redAccent)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _setSleepTimer(int minutes) {
    _sleepTimer?.cancel();
    setState(() => _sleepMinutesRemaining = minutes);
    _sleepTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (!mounted) return;
      setState(() {
        if (_sleepMinutesRemaining != null && _sleepMinutesRemaining! > 1) {
          _sleepMinutesRemaining = _sleepMinutesRemaining! - 1;
        } else {
          timer.cancel();
          _sleepMinutesRemaining = null;
          _engine.stopAndClear();
          SystemNavigator.pop();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _engine,
      builder: (context, _) {
        final ctrl = _engine.controller;
        final isReady = _engine.isReady && ctrl != null;
        final hasError = _engine.hasError;
        final isRecovering = _engine.isRecovering;
        final epg = _engine.currentEpg;
        final prevChannel = _engine.previousChannelItem;
        final qualities = _getQualities();
        final isVod = currentItem.type != ContentType.live;
        final isFav = widget.favoriteIds.contains(currentItem.id);

        // Janela flutuante do Android: só vídeo, sem nenhum controle
        if (_inPip) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: isReady
                  ? _buildAspectVideo(ctrl)
                  : const CircularProgressIndicator(color: Color(0xFF00E5FF)),
            ),
          );
        }

        return PopScope(
          canPop: !showQuickChannelDrawer && !showOsd,
          onPopInvoked: (didPop) {
            if (!didPop) {
              if (showQuickChannelDrawer) {
                setState(() => showQuickChannelDrawer = false);
              } else if (showOsd) {
                setState(() => showOsd = false);
              }
            }
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Focus(
              autofocus: true,
              onKeyEvent: (node, event) {
                if (event is KeyDownEvent) {
                  final key = event.logicalKey;

                  // Teclas físicas de Play/Pause dedicadas no controle
                  if (key == LogicalKeyboardKey.mediaPlayPause ||
                      key == LogicalKeyboardKey.mediaPlay ||
                      key == LogicalKeyboardKey.mediaPause) {
                    _engine.togglePlayPause();
                    _revealOsdWithFade();
                    return KeyEventResult.handled;
                  }

                  // BLOQUEIO ESTRITO: Em hipótese alguma botões Cima/Baixo ou ChannelUp/Down trocam de canal!
                  if (key == LogicalKeyboardKey.channelUp ||
                      key == LogicalKeyboardKey.channelDown) {
                    if (!showOsd) _revealOsdWithFade();
                    return KeyEventResult.handled;
                  }

                  // Quando a interface do player está oculta:
                  if (!showQuickChannelDrawer && !showOsd) {
                    // Botão do meio (OK / Select / Enter) exibe a interface com animação curta de Fade
                    if (key == LogicalKeyboardKey.select ||
                        key == LogicalKeyboardKey.enter ||
                        key == LogicalKeyboardKey.numpadEnter ||
                        key == LogicalKeyboardKey.gameButtonA) {
                      _revealOsdWithFade();
                      return KeyEventResult.handled;
                    }
                    // Setas Cima e Baixo NUNCA trocam de canal: apenas revelam a interface com fade
                    if (key == LogicalKeyboardKey.arrowUp ||
                        key == LogicalKeyboardKey.arrowDown) {
                      _revealOsdWithFade();
                      return KeyEventResult.handled;
                    }
                    // Seta Esquerda: abre a gaveta lateral em TV ao Vivo ou volta 10s em Filmes/Séries
                    if (key == LogicalKeyboardKey.arrowLeft) {
                      if (isVod) {
                        _engine.seekRelative(-10);
                        _revealOsdWithFade();
                      } else {
                        setState(() => showQuickChannelDrawer = true);
                      }
                      return KeyEventResult.handled;
                    }
                    // Seta Direita: avança 10s em Filmes/Séries ou revela o OSD em TV ao Vivo
                    if (key == LogicalKeyboardKey.arrowRight) {
                      if (isVod) {
                        _engine.seekRelative(10);
                      }
                      _revealOsdWithFade();
                      return KeyEventResult.handled;
                    }
                  } else {
                    // Quando a interface já está visível, mantém o timer ativo enquanto o usuário navega pelas setas
                    _resetOsdTimer();
                  }
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (showQuickChannelDrawer) {
                    setState(() => showQuickChannelDrawer = false);
                  } else if (showOsd) {
                    setState(() => showOsd = false);
                  } else {
                    _revealOsdWithFade();
                  }
                },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. VÍDEO PRINCIPAL CONTÍNUO
                    Center(
                      child: hasError
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.wifi_tethering_error_rounded,
                                    color: Colors.redAccent, size: 44),
                                const SizedBox(height: 12),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 32),
                                  child: Text(
                                    _engine.failureMessage,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontSize: 13, height: 1.4),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TVFocusableItem(
                                  autofocus: true,
                                  autoScroll: false,
                                  onSelect: () => _engine.openStream(
                                    currentItem,
                                    forceReload: true,
                                    tryHlsFallback: !_engine.usingHlsFallback,
                                  ),
                                  builder: (context, isFocused) => Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 18, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00E5FF),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isFocused
                                            ? Colors.white
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                    child: const Text(
                                      'Reconectar Fluxo',
                                      style: TextStyle(
                                          color: Colors.black,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            )
                          : isReady
                              ? _buildAspectVideo(ctrl)
                              : const CircularProgressIndicator(
                                  color: Color(0xFF00E5FF)),
                    ),

                    // 2a. AVISO DO FALLBACK AUTOMÁTICO DE CODEC
                    if (_engine.codecNotice != null)
                      Positioned(
                        top: 20,
                        left: 20,
                        right: 20,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.amber),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.amber),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(_engine.codecNotice!,
                                      style: const TextStyle(fontSize: 11)),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // 2. INDICADOR DE SINCRONIZAÇÃO DE BAIXA LATÊNCIA
                    if (isRecovering)
                      Positioned(
                        top: 20,
                        right: 20,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF00E5FF)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Color(0xFF00E5FF)),
                              ),
                              SizedBox(width: 8),
                              Text('Estabilizando sinal ao vivo...',
                                  style: TextStyle(fontSize: 11)),
                            ],
                          ),
                        ),
                      ),

                    // 3. LEGENDA DISCRETA DE AJUDA AO ABRIR O PLAYER (SOME SOZINHA EM 3S)
                    Positioned(
                      top: 22,
                      left: 0,
                      right: 0,
                      child: IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: (showStartupHint && !showOsd) ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: const Text(
                                'Aperte OK no controle para abrir os controles do Player • ◄ Lista Rápida',
                                style: TextStyle(
                                    fontSize: 11, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. INTERFACE DO PLAYER COM ANIMAÇÃO CURTA DE FADE (180ms)
                    IgnorePointer(
                      ignoring: !showOsd,
                      child: AnimatedOpacity(
                        opacity: showOsd ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.black87,
                                Colors.transparent,
                                Colors.transparent,
                                Colors.black87,
                              ],
                            ),
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // TOPO DO PLAYER
                              Row(
                                children: [
                                  TVIconButton(
                                    icon: Icons.arrow_back_ios_new_rounded,
                                    tooltip: 'Voltar ao catálogo mantendo vídeo',
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                  TVIconButton(
                                    icon: Icons.menu_open_rounded,
                                    color: const Color(0xFF00E5FF),
                                    tooltip: 'Gaveta Rápida de Canais',
                                    onPressed: () => setState(() =>
                                        showQuickChannelDrawer =
                                            !showQuickChannelDrawer),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          currentItem.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold),
                                        ),
                                        Text(
                                          currentItem.group,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11,
                                              color: Color(0xFF00E5FF)),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Botão de Favoritar dentro do Player
                                  TVIconButton(
                                    icon: isFav
                                        ? Icons.star_rounded
                                        : Icons.star_border_rounded,
                                    color: isFav ? Colors.amber : Colors.white70,
                                    tooltip: 'Favoritar / Desfavoritar',
                                    onPressed: () {
                                      widget.onToggleFavorite(currentItem);
                                      setState(() {});
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  if (_sleepMinutesRemaining != null)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '${_sleepMinutesRemaining}m',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Colors.amber,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  TVIconButton(
                                    icon: Icons.bedtime_outlined,
                                    tooltip: 'Timer de Sono',
                                    onPressed: _openSleepTimerModal,
                                  ),
                                  const SizedBox(width: 4),
                                  TVFocusableItem(
                                    autoScroll: false,
                                    onSelect: () {
                                      setState(() => aspectMode =
                                          (aspectMode + 1) %
                                              aspectLabels.length);
                                    },
                                    builder: (context, isFocused) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isFocused
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white12,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? Colors.white
                                              : Colors.white24,
                                        ),
                                      ),
                                      child: Text(
                                        aspectLabels[aspectMode],
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: isFocused
                                              ? Colors.black
                                              : Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  if (_isMobile && _pipSupported) ...[
                                    TVIconButton(
                                      icon: Icons.picture_in_picture_rounded,
                                      color: const Color(0xFF00E5FF),
                                      tooltip: 'PiP do Android (sobre outros apps)',
                                      onPressed: () async {
                                        final ok = await NativeBridge.enterPip();
                                        if (!ok && mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(const SnackBar(
                                            content: Text(
                                                'PiP indisponível neste aparelho.'),
                                          ));
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  TVIconButton(
                                    icon:
                                        Icons.picture_in_picture_alt_rounded,
                                    color: const Color(0xFF00E5FF),
                                    tooltip: 'Minimizar em PiP',
                                    onPressed: () {
                                      Navigator.pop(context);
                                      widget.onMinimizeToPip(currentItem);
                                    },
                                  ),
                                ],
                              ),

                              // RODAPÉ DO PLAYER: EPG + BOTÕES DE SETA (ÚNICO LUGAR QUE TROCA DE CANAL)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF10131D).withOpacity(0.94),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // GUIA EPG AO VIVO
                                    if (!isVod && epg != null) ...[
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.redAccent,
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: const Text(
                                              'AGORA',
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              epg.nowTitle,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: Text(
                                              'A Seguir: ${epg.nextTitle}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF00E5FF),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                    ],

                                    // BARRA DE TEMPO (FILMES E SÉRIES)
                                    if (isVod && isReady)
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 8.0),
                                        child: Column(
                                          children: [
                                            VideoProgressIndicator(
                                              ctrl,
                                              allowScrubbing: true,
                                              colors: const VideoProgressColors(
                                                playedColor: Color(0xFF00E5FF),
                                                bufferedColor: Colors.white24,
                                                backgroundColor: Colors.white10,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  _formatDuration(
                                                      ctrl.value.position),
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70),
                                                ),
                                                Text(
                                                  _formatDuration(
                                                      ctrl.value.duration),
                                                  style: const TextStyle(
                                                      fontSize: 10,
                                                      color: Colors.white70),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),

                                    // LINHA PRINCIPAL: SETA ANTERIOR | PLAY/PAUSE | SETA PRÓXIMO + RECALL + QUALIDADES
                                    Row(
                                      children: [
                                        // Botão de Seta Esquerda (Canal Anterior) ao lado do Play/Pause
                                        TVFocusableItem(
                                          autoScroll: false,
                                          onSelect: () =>
                                              _stepChannelByButton(-1),
                                          builder: (context, isFocused) =>
                                              AnimatedScale(
                                            scale: isFocused ? 1.14 : 1.0,
                                            duration: const Duration(
                                                milliseconds: 110),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isFocused
                                                    ? const Color(0xFF00E5FF)
                                                    : Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isFocused
                                                      ? Colors.white
                                                      : Colors.white12,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.skip_previous_rounded,
                                                color: isFocused
                                                    ? Colors.black
                                                    : Colors.white,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),

                                        if (isVod) ...[
                                          TVIconButton(
                                            icon: Icons.replay_10_rounded,
                                            tooltip: 'Voltar 10s',
                                            onPressed: () =>
                                                _engine.seekRelative(-10),
                                          ),
                                          const SizedBox(width: 4),
                                        ],

                                        // Botão Central de Play / Pause
                                        TVFocusableItem(
                                          focusNode: _playPauseFocusNode,
                                          autofocus: true,
                                          autoScroll: false,
                                          onSelect: () {
                                            _engine.togglePlayPause();
                                            _resetOsdTimer();
                                          },
                                          builder: (context, isFocused) =>
                                              AnimatedScale(
                                            scale: isFocused ? 1.15 : 1.0,
                                            duration: const Duration(
                                                milliseconds: 110),
                                            child: Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(
                                                color: isFocused
                                                    ? const Color(0xFF00E5FF)
                                                        .withOpacity(0.25)
                                                    : Colors.transparent,
                                                shape: BoxShape.circle,
                                                border: Border.all(
                                                  color: isFocused
                                                      ? const Color(0xFF00E5FF)
                                                      : Colors.transparent,
                                                  width: 2,
                                                ),
                                              ),
                                              child: Icon(
                                                isReady && ctrl.value.isPlaying
                                                    ? Icons
                                                        .pause_circle_filled_rounded
                                                    : Icons
                                                        .play_circle_fill_rounded,
                                                color: const Color(0xFF00E5FF),
                                                size: 36,
                                              ),
                                            ),
                                          ),
                                        ),

                                        if (isVod) ...[
                                          const SizedBox(width: 4),
                                          TVIconButton(
                                            icon: Icons.forward_10_rounded,
                                            tooltip: 'Avançar 10s',
                                            onPressed: () =>
                                                _engine.seekRelative(10),
                                          ),
                                        ],

                                        const SizedBox(width: 6),
                                        // Botão de Seta Direita (Próximo Canal) ao lado do Play/Pause
                                        TVFocusableItem(
                                          autoScroll: false,
                                          onSelect: () =>
                                              _stepChannelByButton(1),
                                          builder: (context, isFocused) =>
                                              AnimatedScale(
                                            scale: isFocused ? 1.14 : 1.0,
                                            duration: const Duration(
                                                milliseconds: 110),
                                            child: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: isFocused
                                                    ? const Color(0xFF00E5FF)
                                                    : Colors.white10,
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: isFocused
                                                      ? Colors.white
                                                      : Colors.white12,
                                                  width: 1.5,
                                                ),
                                              ),
                                              child: Icon(
                                                Icons.skip_next_rounded,
                                                color: isFocused
                                                    ? Colors.black
                                                    : Colors.white,
                                                size: 22,
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Botão "Último Canal" (Recall) para alternar rápido entre 2 canais
                                        if (!isVod &&
                                            prevChannel != null &&
                                            prevChannel.id !=
                                                currentItem.id) ...[
                                          const SizedBox(width: 10),
                                          TVFocusableItem(
                                            autoScroll: false,
                                            onSelect: _recallPreviousChannel,
                                            builder: (context, isFocused) =>
                                                Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: isFocused
                                                    ? const Color(0xFF00E5FF)
                                                    : const Color(0xFF172238),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: isFocused
                                                      ? Colors.white
                                                      : const Color(0xFF00E5FF)
                                                          .withOpacity(0.4),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.swap_horiz_rounded,
                                                    size: 14,
                                                    color: isFocused
                                                        ? Colors.black
                                                        : const Color(
                                                            0xFF00E5FF),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Último Canal',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isFocused
                                                          ? Colors.black
                                                          : Colors.white,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],

                                        const SizedBox(width: 10),
                                        // Seletor Rápido de Qualidade (SD / HD / FHD / 4K)
                                        Expanded(
                                          child: SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(
                                              children: qualities.map((q) {
                                                final isCurrent =
                                                    q.id == currentItem.id;
                                                return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          right: 6),
                                                  child: TVFocusableItem(
                                                    autoScroll: false,
                                                    onSelect: () =>
                                                        _switchStream(q),
                                                    builder: (context,
                                                            isFocused) =>
                                                        Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 10,
                                                          vertical: 5),
                                                      decoration: BoxDecoration(
                                                        color: isCurrent
                                                            ? const Color(
                                                                0xFF00E5FF)
                                                            : Colors.white12,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(6),
                                                        border: Border.all(
                                                          color: isFocused
                                                              ? Colors.white
                                                              : Colors
                                                                  .transparent,
                                                          width: 1.5,
                                                        ),
                                                      ),
                                                      child: Text(
                                                        q.qualityTag,
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: isCurrent
                                                              ? Colors.black
                                                              : Colors.white,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }).toList(),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // 4b. GESTOS DE BRILHO / VOLUME / TEMPO (SOMENTE CELULAR)
                    _buildGestureLayer(),
                    if (_isMobile) _buildGestureIndicator(),

                    // 5. CARD FLUTUANTE DE "PRÓXIMO EPISÓDIO AUTOMÁTICO" (EM SÉRIES)
                    if (_nextEpisodeCountdown != null &&
                        _upcomingEpisodeItem != null)
                      Positioned(
                        bottom: 95,
                        right: 24,
                        child: Container(
                          width: 300,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101420).withOpacity(0.96),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: const Color(0xFF00E5FF), width: 1.5),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.7),
                                blurRadius: 20,
                              )
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'PRÓXIMO EPISÓDIO EM ${_nextEpisodeCountdown}s...',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF00E5FF),
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _upcomingEpisodeItem!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TVFocusableItem(
                                    autoScroll: false,
                                    onSelect: _cancelAutoPlayNext,
                                    builder: (context, isFocused) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? Colors.white
                                              : Colors.white24,
                                        ),
                                      ),
                                      child: const Text('Cancelar',
                                          style: TextStyle(fontSize: 11)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  TVFocusableItem(
                                    autofocus: true,
                                    autoScroll: false,
                                    onSelect: () {
                                      final target = _upcomingEpisodeItem!;
                                      _cancelAutoPlayNext();
                                      _switchStream(target);
                                    },
                                    builder: (context, isFocused) => Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF00E5FF),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? Colors.white
                                              : Colors.transparent,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Text(
                                        'Assistir Agora',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.black,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                    // 6. GAVETA LATERAL DE CANAIS / EPISÓDIOS
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      top: 0,
                      bottom: 0,
                      left: showQuickChannelDrawer ? 0 : -290,
                      width: 280,
                      child: Container(
                        color: const Color(0xFF08090E).withOpacity(0.95),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(14.0),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    isVod ? 'EPISÓDIOS / LISTA' : 'CANAIS',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF00E5FF)),
                                  ),
                                  TVIconButton(
                                    icon: Icons.close,
                                    onPressed: () => setState(
                                        () => showQuickChannelDrawer = false),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                itemCount: widget.playlist.length,
                                itemBuilder: (context, idx) {
                                  final ch = widget.playlist[idx];
                                  final selected = ch.id == currentItem.id;
                                  return TVFocusableItem(
                                    autofocus:
                                        selected && showQuickChannelDrawer,
                                    onSelect: () {
                                      setState(
                                          () => showQuickChannelDrawer = false);
                                      if (ch.id != currentItem.id) {
                                        _switchStream(ch);
                                      }
                                    },
                                    builder: (context, isFocused) => Container(
                                      margin: const EdgeInsets.symmetric(
                                          vertical: 2),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? const Color(0xFF00E5FF)
                                                .withOpacity(0.2)
                                            : isFocused
                                                ? Colors.white10
                                                : Colors.transparent,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isFocused
                                              ? const Color(0xFF00E5FF)
                                              : Colors.transparent,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              ch.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            ch.qualityTag,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Color(0xFF00E5FF),
                                                fontWeight: FontWeight.bold),
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
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAspectVideo(VideoPlayerController ctrl) {
    if (aspectMode == 1) {
      return SizedBox.expand(child: VideoPlayer(ctrl));
    } else if (aspectMode == 2) {
      return AspectRatio(aspectRatio: 16 / 9, child: VideoPlayer(ctrl));
    } else if (aspectMode == 3) {
      return AspectRatio(aspectRatio: 4 / 3, child: VideoPlayer(ctrl));
    }
    return AspectRatio(
      aspectRatio: ctrl.value.aspectRatio,
      child: VideoPlayer(ctrl),
    );
  }
}
