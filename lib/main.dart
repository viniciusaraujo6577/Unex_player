import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

import 'account_service.dart';
import 'codec_support.dart';
import 'core.dart';
import 'image_cache.dart';
import 'mobile_screen.dart';
import 'native_bridge.dart';
import 'player_screen.dart';
import 'tv_screen.dart';
import 'update_service.dart';
import 'vod_metadata.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  NativeBridge.init();
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('Erro de widget: ${details.exceptionAsString()}');
    return const SizedBox.shrink();
  };

  // Limite estrito de RAM para imagens (perfil conforme a memória do aparelho)
  await ImageMemory.configure();
  // Descobre quais decoders de áudio o hardware possui (AC3, E-AC3, DTS)
  unawaited(CodecSupport.probe());

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const UnexVisionApp());
}

class UnexVisionApp extends StatefulWidget {
  const UnexVisionApp({super.key});

  @override
  State<UnexVisionApp> createState() => _UnexVisionAppState();
}

class _UnexVisionAppState extends State<UnexVisionApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // O Android pode matar o processo a qualquer momento depois daqui:
    // garante que favoritos/histórico/progresso já estão gravados no disco.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      AppStorage.flushAll();
    }
  }

  @override
  void didHaveMemoryPressure() {
    ImageMemory.trimMemory();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNEX Vision',
      debugShowCheckedModeBanner: false,
      shortcuts: <ShortcutActivator, Intent>{
        ...WidgetsApp.defaultShortcuts,
        const SingleActivator(LogicalKeyboardKey.select): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.enter): const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.numpadEnter):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.gameButtonA):
            const ActivateIntent(),
        const SingleActivator(LogicalKeyboardKey.space): const ActivateIntent(),
      },
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF08090E),
        primaryColor: const Color(0xFF00E5FF),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF00E5FF),
          secondary: Color(0xFF2979FF),
          surface: Color(0xFF12151F),
        ),
      ),
      home: const StartupRouterScreen(),
    );
  }
}

class StartupRouterScreen extends StatefulWidget {
  const StartupRouterScreen({super.key});

  @override
  State<StartupRouterScreen> createState() => _StartupRouterScreenState();
}

class _StartupRouterScreenState extends State<StartupRouterScreen> {
  @override
  void initState() {
    super.initState();
    _boot();
  }

  /// Detecção automática (Android TV x celular). Só pergunta ao usuário se
  /// a detecção falhar E ainda não houver nenhuma preferência salva.
  /// Se o usuário escolheu manualmente (ex.: firmware de TV Box modificado),
  /// a escolha manual sempre prevalece.
  Future<DeviceMode?> _resolveDeviceMode() async {
    final prefs = await AppStorage.loadDevicePrefs();
    if (prefs != null && prefs.manual) return prefs.mode;

    final isTv = await NativeBridge.isTelevision();
    if (isTv == null) return prefs?.mode; // detecção indisponível
    final detected = isTv ? DeviceMode.tv : DeviceMode.mobile;
    if (prefs == null || prefs.mode != detected || prefs.manual) {
      await AppStorage.saveDeviceMode(detected, manual: false);
    }
    return detected;
  }

  Future<void> _boot() async {
    final mode = await _resolveDeviceMode();
    if (!mounted) return;

    if (mode == null) {
      Navigator.pushReplacement(
        context,
        createSmoothRoute(const DeviceSelectionScreen()),
      );
    } else {
      await applyDeviceOrientation(mode);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        createSmoothRoute(
          LoginGatewayScreen(
            deviceMode: mode,
            allowAutoLogin: true,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
    );
  }
}

class DeviceSelectionScreen extends StatelessWidget {
  const DeviceSelectionScreen({super.key});

  Future<void> _selectAuto(BuildContext context) async {
    await AppStorage.clearDeviceMode();
    if (!context.mounted) return;
    Navigator.pushReplacement(
      context,
      createSmoothRoute(const StartupRouterScreen()),
    );
  }

  Future<void> _selectMode(BuildContext context, DeviceMode mode) async {
    await AppStorage.saveDeviceMode(mode, manual: true);
    await applyDeviceOrientation(mode);
    if (!context.mounted) return;

    Navigator.pushReplacement(
      context,
      createSmoothRoute(
        LoginGatewayScreen(
          deviceMode: mode,
          allowAutoLogin: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) showExitAppConfirmationDialog(context);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topCenter,
              radius: 1.5,
              colors: [Color(0xFF132238), Color(0xFF08090E)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF2979FF)],
                          ),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const Icon(Icons.devices_rounded,
                            color: Colors.black, size: 38),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'BEM-VINDO AO UNEX VISION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Não conseguimos identificar o aparelho automaticamente.\nEscolha abaixo — você pode mudar depois nas opções do app.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white60, fontSize: 14),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        spacing: 20,
                        runSpacing: 20,
                        alignment: WrapAlignment.center,
                        children: [
                          _buildCard(
                            context: context,
                            title: 'Celular Android',
                            subtitle:
                                'Interface vertical para tela de toque com menu lateral deslizante.',
                            icon: Icons.smartphone_rounded,
                            autofocus: false,
                            onTap: () =>
                                _selectMode(context, DeviceMode.mobile),
                          ),
                          _buildCard(
                            context: context,
                            title: 'TV Android / TV Box',
                            subtitle:
                                'Interface Widescreen 100% controlada por controle remoto e teclado de TV próprio.',
                            icon: Icons.tv_rounded,
                            autofocus: true,
                            onTap: () => _selectMode(context, DeviceMode.tv),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TVFocusableItem(
                        autoScroll: false,
                        onSelect: () => _selectAuto(context),
                        builder: (context, isFocused) => Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isFocused
                                  ? const Color(0xFF00E5FF)
                                  : Colors.white12,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.auto_awesome_rounded,
                                  size: 16, color: Color(0xFF00E5FF)),
                              SizedBox(width: 8),
                              Text('Detectar automaticamente',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF00E5FF))),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool autofocus,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 290,
      child: TVFocusableItem(
        autofocus: autofocus,
        autoScroll: false,
        onSelect: onTap,
        builder: (context, isFocused) => AnimatedScale(
          scale: isFocused ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 140),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF12151F),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isFocused ? const Color(0xFF00E5FF) : Colors.white12,
                width: isFocused ? 2.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00E5FF).withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: const Color(0xFF00E5FF), size: 42),
                ),
                const SizedBox(height: 16),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(subtitle,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.white60, height: 1.4)),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Center(
                    child: Text(
                      'SELECIONAR',
                      style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LoginGatewayScreen extends StatefulWidget {
  final DeviceMode deviceMode;
  final bool allowAutoLogin;
  final String initialDns;
  final String initialUser;
  final String initialPass;
  final String initialM3u;
  final bool initialDirectM3uMode;
  final String? errorBannerMessage;

  const LoginGatewayScreen({
    super.key,
    required this.deviceMode,
    this.allowAutoLogin = false,
    this.initialDns = '',
    this.initialUser = '',
    this.initialPass = '',
    this.initialM3u = '',
    this.initialDirectM3uMode = false,
    this.errorBannerMessage,
  });

  @override
  State<LoginGatewayScreen> createState() => _LoginGatewayScreenState();
}

class _LoginGatewayScreenState extends State<LoginGatewayScreen> {
  late final TextEditingController _dnsController;
  late final TextEditingController _userController;
  late final TextEditingController _passController;
  late final TextEditingController _m3uController;

  late bool _useDirectM3uMode;
  final bool _rememberMe = true;
  bool _checkingSavedSession = false;

  @override
  void initState() {
    super.initState();
    _dnsController = TextEditingController(text: widget.initialDns);
    _userController = TextEditingController(text: widget.initialUser);
    _passController = TextEditingController(text: widget.initialPass);
    _m3uController = TextEditingController(text: widget.initialM3u);
    _useDirectM3uMode = widget.initialDirectM3uMode;

    if (widget.allowAutoLogin) {
      _checkingSavedSession = true;
      _checkAndRestoreVerifiedSession();
    }
  }

  @override
  void dispose() {
    _dnsController.dispose();
    _userController.dispose();
    _passController.dispose();
    _m3uController.dispose();
    super.dispose();
  }

  Future<void> _checkAndRestoreVerifiedSession() async {
    final saved = await AppStorage.loadVerifiedSession();
    if (!mounted) return;

    if (saved != null) {
      final mode = saved['mode']?.toString() ?? 'xtream';
      if (mode == 'm3u') {
        final directUrl = saved['m3uUrl']?.toString() ?? '';
        if (directUrl.isNotEmpty) {
          _openDashboard(directM3uUrl: directUrl, rememberSession: true);
          return;
        }
      } else {
        final dns = saved['dns']?.toString() ?? '';
        final user = saved['user']?.toString() ?? '';
        final pass = saved['pass']?.toString() ?? '';
        if (dns.isNotEmpty && user.isNotEmpty && pass.isNotEmpty) {
          _openDashboard(
              dns: dns, user: user, pass: pass, rememberSession: true);
          return;
        }
      }
    }
    setState(() => _checkingSavedSession = false);
  }

  void _handleLoginSubmit() {
    FocusScope.of(context).unfocus();

    if (_useDirectM3uMode) {
      String rawM3u = _m3uController.text.trim();
      if (rawM3u.isEmpty) {
        _showErrorSnackBar('Informe o link M3U completo.');
        return;
      }
      if (!rawM3u.startsWith('http://') && !rawM3u.startsWith('https://')) {
        rawM3u = 'http://$rawM3u';
      }
      _openDashboard(directM3uUrl: rawM3u, rememberSession: _rememberMe);
    } else {
      String dns = _dnsController.text.trim();
      final user = _userController.text.trim();
      final pass = _passController.text.trim();

      if (dns.isEmpty || user.isEmpty || pass.isEmpty) {
        _showErrorSnackBar('Preencha a URL (DNS), o Usuário e a Senha.');
        return;
      }
      if (!dns.startsWith('http://') && !dns.startsWith('https://')) {
        dns = 'http://$dns';
      }
      while (dns.endsWith('/')) {
        dns = dns.substring(0, dns.length - 1);
      }
      _openDashboard(
          dns: dns, user: user, pass: pass, rememberSession: _rememberMe);
    }
  }

  void _openDashboard({
    String dns = '',
    String user = '',
    String pass = '',
    String? directM3uUrl,
    required bool rememberSession,
  }) {
    Navigator.pushReplacement(
      context,
      createSmoothRoute(
        MainDashboard(
          deviceMode: widget.deviceMode,
          serverDns: dns,
          username: user,
          password: pass,
          directM3uUrl: directM3uUrl,
          rememberSession: rememberSession,
        ),
      ),
    );
  }

  void _showErrorSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_checkingSavedSession) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) showExitAppConfirmationDialog(context);
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.topRight,
              radius: 1.4,
              colors: [Color(0xFF132238), Color(0xFF08090E)],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12151F).withOpacity(0.95),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.06),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    widget.deviceMode == DeviceMode.tv
                                        ? Icons.tv_rounded
                                        : Icons.smartphone_rounded,
                                    size: 14,
                                    color: const Color(0xFF00E5FF),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.deviceMode == DeviceMode.tv
                                        ? 'Modo TV Android'
                                        : 'Modo Celular',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.white70),
                                  ),
                                ],
                              ),
                            ),
                            TVFocusableItem(
                              autoScroll: false,
                              onSelect: () {
                                Navigator.pushReplacement(
                                  context,
                                  createSmoothRoute(
                                      const DeviceSelectionScreen()),
                                );
                              },
                              builder: (context, isFocused) => Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isFocused
                                        ? const Color(0xFF00E5FF)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: const Text(
                                  'Trocar Dispositivo',
                                  style: TextStyle(
                                      fontSize: 11, color: Color(0xFF00E5FF)),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.live_tv_rounded,
                              color: Colors.black, size: 32),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'UNEX VISION',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _useDirectM3uMode
                              ? 'Informe o link M3U completo da sua lista'
                              : 'Selecione cada campo abaixo para preencher',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12),
                        ),
                        if (widget.errorBannerMessage != null) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.5)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline,
                                    color: Colors.redAccent, size: 18),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    widget.errorBannerMessage!,
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.white),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        if (!_useDirectM3uMode) ...[
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _dnsController,
                            label: 'URL / DNS do Servidor',
                            hint: 'Ex: http://cdn4k.club',
                            icon: Icons.dns_rounded,
                            isUrlField: true,
                          ),
                          const SizedBox(height: 10),
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _userController,
                            label: 'Usuário',
                            hint: 'Digite seu usuário',
                            icon: Icons.person_outline_rounded,
                          ),
                          const SizedBox(height: 10),
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _passController,
                            label: 'Senha',
                            hint: 'Digite sua senha',
                            icon: Icons.lock_outline_rounded,
                            isPassword: true,
                            onSubmitted: _handleLoginSubmit,
                          ),
                        ] else ...[
                          AdaptiveInputField(
                            deviceMode: widget.deviceMode,
                            controller: _m3uController,
                            label: 'Link M3U Completo',
                            hint: 'http://.../get.php?username=...&password=...',
                            icon: Icons.link_rounded,
                            isUrlField: true,
                            onSubmitted: _handleLoginSubmit,
                          ),
                        ],
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: TVFocusableItem(
                            autoScroll: false,
                            onSelect: _handleLoginSubmit,
                            builder: (context, isFocused) => Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [
                                  Color(0xFF00E5FF),
                                  Color(0xFF2979FF)
                                ]),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isFocused
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'CONECTAR AGORA',
                                  style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TVFocusableItem(
                          autoScroll: false,
                          onSelect: () => setState(
                              () => _useDirectM3uMode = !_useDirectM3uMode),
                          builder: (context, isFocused) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isFocused
                                    ? const Color(0xFF00E5FF)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _useDirectM3uMode
                                      ? Icons.vpn_key_outlined
                                      : Icons.link_rounded,
                                  size: 15,
                                  color: Colors.white54,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _useDirectM3uMode
                                      ? 'Usar acesso com URL, Usuário e Senha'
                                      : 'Inserir código / link M3U diretamente',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.white54),
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
            ),
          ),
        ),
      ),
    );
  }
}

class MainDashboard extends StatefulWidget {
  final DeviceMode deviceMode;
  final String serverDns;
  final String username;
  final String password;
  final String? directM3uUrl;
  final bool rememberSession;

  const MainDashboard({
    super.key,
    required this.deviceMode,
    required this.serverDns,
    required this.username,
    required this.password,
    this.directM3uUrl,
    this.rememberSession = true,
  });

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final SharedStreamEngine _engine = SharedStreamEngine.instance;

  late DeviceMode currentDeviceMode;
  bool isTVSideMenuOpen = false;

  List<StreamItem> allItems = [];
  List<StreamItem> liveItems = [];
  List<StreamItem> movieItems = [];
  List<StreamItem> seriesItems = [];
  List<SeriesGroup> allSeriesGroups = [];

  // Mapas pré-indexados O(1) para troca de categoria em 0ms
  final Map<String, List<StreamItem>> _liveByGroup = {};
  final Map<String, List<StreamItem>> _movieByGroup = {};
  final Map<String, List<SeriesGroup>> _seriesByGroup = {};

  List<StreamItem> displayedItems = [];
  List<SeriesGroup> displayedSeries = [];
  Map<String, VodProgressEntry> vodProgressMap = {};

  Map<String, int> categoryCounts = {};
  List<String> sectionCategories = ['Todas'];

  MainSection activeSection = MainSection.live;
  String selectedCategory = 'Todas';
  String searchQuery = '';
  Timer? _searchDebounce;

  Set<String> favoriteIds = {};
  List<StreamItem> recentItems = [];
  String parentalPin = '0000';
  bool adultUnlocked = false;

  String accountExpDate = '';
  AccountStatus accountStatus = AccountStatus.unknown;
  bool _warnedExpiry = false;
  bool _legacyIdsChecked = false;
  static bool _updateChecked = false;
  bool _checkingAccountAgain = false;
  final Map<String, Future<SeriesMetadata?>> _seriesMetaFutures = {};
  double lastMeasuredSpeedMbps = 18.5;
  bool isLoading = true;
  String errorMessage = '';
  bool isMiniPipFloating = false;

  final TextEditingController _searchController = TextEditingController();

  bool get isDirectM3u =>
      widget.directM3uUrl != null && widget.directM3uUrl!.trim().isNotEmpty;

  String get m3uUrl {
    if (isDirectM3u) return widget.directM3uUrl!.trim();
    return '${widget.serverDns}/get.php?username=${widget.username}&password=${widget.password}&type=m3u_plus&output=ts';
  }

  /// Credenciais Xtream (login direto OU extraídas de um link get.php).
  ({String dns, String user, String pass})? get _xtreamCreds {
    if (!isDirectM3u) {
      return (dns: widget.serverDns, user: widget.username, pass: widget.password);
    }
    return AccountService.credentialsFromM3u(m3uUrl);
  }

  List<VodProgressEntry> get sortedContinueWatching {
    final list = vodProgressMap.values.toList();
    list.sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  @override
  void initState() {
    super.initState();
    currentDeviceMode = widget.deviceMode;
    applyDeviceOrientation(currentDeviceMode);

    _engine.addListener(_onEngineUpdated);
    _engine.onVodProgressSaved = (entry) {
      if (!mounted) return;
      setState(() {
        if (entry.progress >= 0.96) {
          vodProgressMap.remove(entry.item.id);
        } else {
          vodProgressMap[entry.item.id] = entry;
        }
        if (activeSection == MainSection.continueWatching) {
          _rebuildSectionCategories();
        }
      });
    };

    _initSavedProgressAndPlaylist();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _engine.removeListener(_onEngineUpdated);
    _engine.onVodProgressSaved = null;
    _searchController.dispose();
    super.dispose();
  }

  void _onEngineUpdated() {
    if (mounted) setState(() {});
  }

  Future<void> _initSavedProgressAndPlaylist() async {
    // Tudo em paralelo: disco é rápido, mas não precisa ser sequencial.
    final progressF = AppStorage.loadVodProgressMap();
    final favF = AppStorage.loadFavorites();
    final recentF = AppStorage.loadRecents();
    final lastF = AppStorage.loadLastChannel();
    final cachedAccountF = AccountService.cached();

    vodProgressMap = await progressF;
    favoriteIds = await favF;
    recentItems = await recentF;

    // 1) Conta vencida (último estado conhecido) bloqueia ANTES de tocar vídeo.
    final cachedAccount = await cachedAccountF;
    if (cachedAccount.blocksAccess) {
      if (!mounted) return;
      setState(() {
        accountStatus = cachedAccount;
        accountExpDate = cachedAccount.formattedExpiry;
        isLoading = false;
      });
      _validateAccount(); // pode ter renovado: confirma online
      return;
    }

    // 2) Último canal assistido começa a tocar IMEDIATAMENTE (enquanto o
    //    catálogo ainda está sendo lido do disco).
    final lastChannel = await lastF;
    _configureEngineCredentials();
    if (lastChannel != null && !(lastChannel.isAdult)) {
      unawaited(_engine.openStream(lastChannel));
    }

    await _loadAccountInfoAndPlaylist(forceNetwork: false);
    _scheduleUpdateCheck();
  }

  void _configureEngineCredentials() {
    final c = _xtreamCreds;
    _engine.configureCredentials(
      dns: c?.dns ?? '',
      user: c?.user ?? '',
      pass: c?.pass ?? '',
      speedMbps: lastMeasuredSpeedMbps,
    );
  }

  // ---------------------------------------------------------------------------
  // VALIDAÇÃO DE VENCIMENTO / CONTA
  // ---------------------------------------------------------------------------
  Future<void> _validateAccount() async {
    final c = _xtreamCreds;
    if (c == null) return; // M3U genérico: não há API para validar
    final fresh =
        await AccountService.check(dns: c.dns, user: c.user, pass: c.pass);
    if (fresh.state == AccountState.unknown) return; // sem rede: mantém o cache
    _applyAccountStatus(fresh);
  }

  void _applyAccountStatus(AccountStatus st) {
    if (!mounted) return;
    final wasBlocked = accountStatus.blocksAccess;
    setState(() {
      accountStatus = st;
      accountExpDate = st.formattedExpiry;
    });
    if (st.blocksAccess) {
      _engine.stopAndClear();
    } else if (wasBlocked && playlistIsEmpty) {
      // conta renovada: carrega o catálogo
      _loadAccountInfoAndPlaylist(forceNetwork: false);
    }
    if (st.expiresSoon && !_warnedExpiry) {
      _warnedExpiry = true;
      final d = st.daysLeft ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.orange.shade800,
          content: Text(d <= 1
              ? 'Sua assinatura vence hoje/amanhã (${st.formattedExpiry}). Renove para não perder o acesso.'
              : 'Sua assinatura vence em $d dias (${st.formattedExpiry}).'),
        ),
      );
    }
  }

  bool get playlistIsEmpty => allItems.isEmpty;

  Future<void> _recheckBlockedAccount() async {
    if (_checkingAccountAgain) return;
    setState(() => _checkingAccountAgain = true);
    final c = _xtreamCreds;
    if (c != null) {
      final fresh =
          await AccountService.check(dns: c.dns, user: c.user, pass: c.pass);
      if (fresh.state != AccountState.unknown) {
        _applyAccountStatus(fresh);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Sem conexão para verificar agora. Tente novamente.'),
        ));
      }
    }
    if (mounted) setState(() => _checkingAccountAgain = false);
  }

  // ---------------------------------------------------------------------------
  // ATUALIZAÇÃO REMOTA (OTA)
  // ---------------------------------------------------------------------------
  void _scheduleUpdateCheck() {
    if (_updateChecked) return;
    _updateChecked = true;
    Future.delayed(const Duration(seconds: 4), () async {
      final info = await UpdateService.checkForUpdate();
      if (info != null && mounted && !accountStatus.blocksAccess) {
        showUpdateDialog(context, info);
      }
    });
  }

  Future<void> _switchDeviceMode() async {
    final nextMode = currentDeviceMode == DeviceMode.mobile
        ? DeviceMode.tv
        : DeviceMode.mobile;
    await AppStorage.saveDeviceMode(nextMode, manual: true);
    await applyDeviceOrientation(nextMode);
    if (!mounted) return;
    setState(() => currentDeviceMode = nextMode);
  }

  Future<void> _returnToLoginForEditing({String? errorBanner}) async {
    await _engine.stopAndClear();
    await AppStorage.clearSession();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      createSmoothRoute(
        LoginGatewayScreen(
          deviceMode: currentDeviceMode,
          allowAutoLogin: false,
          initialDns: widget.serverDns,
          initialUser: widget.username,
          initialPass: widget.password,
          initialM3u: widget.directM3uUrl ?? '',
          initialDirectM3uMode: isDirectM3u,
          errorBannerMessage: errorBanner,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CATÁLOGO: cache local instantâneo + sincronização silenciosa
  // ---------------------------------------------------------------------------
  Future<void> _applyCatalog(CatalogData d, {bool silent = false}) async {
    if (d.isEmpty) return;

    // 1x: converte IDs antigos (posição_hash) para IDs estáveis
    if (!_legacyIdsChecked) {
      _legacyIdsChecked = true;
      final migrated = await AppStorage.migrateLegacyIds(
        catalog: d.all,
        favorites: favoriteIds,
        progress: vodProgressMap,
        recents: recentItems,
      );
      if (migrated.changed) {
        favoriteIds = migrated.favorites;
        vodProgressMap = migrated.progress;
        recentItems = migrated.recents;
      }
    }

    if (!mounted) return;
    setState(() {
      allItems = d.all;
      liveItems = d.live;
      movieItems = d.movies;
      seriesItems = d.seriesEpisodes;
      allSeriesGroups = d.seriesGroups;

      _liveByGroup
        ..clear()
        ..addAll(d.liveByGroup);
      _movieByGroup
        ..clear()
        ..addAll(d.movieByGroup);
      _seriesByGroup
        ..clear()
        ..addAll(d.seriesByGroup);

      if (!silent) {
        activeSection = d.live.isNotEmpty
            ? MainSection.live
            : d.movies.isNotEmpty
                ? MainSection.movie
                : MainSection.series;
        isTVSideMenuOpen = false;
      }
      _rebuildSectionCategories();
      isLoading = false;
    });

    // Sem último canal salvo: pré-visualiza o 1º canal ao vivo (nunca um filme).
    if (!silent && d.live.isNotEmpty && _engine.currentItem == null) {
      _startPreview(d.live.first, forcePreviewOnly: true);
    }
  }

  Future<void> _loadAccountInfoAndPlaylist({bool forceNetwork = false}) async {
    _configureEngineCredentials();
    unawaited(_validateAccount()); // não bloqueia a abertura

    // 1) Cache local já processado => interface em ~1s, rede só em 2º plano.
    if (!forceNetwork) {
      try {
        final cachedJson = await AppStorage.loadCatalogJson(m3uUrl);
        if (cachedJson != null && cachedJson.isNotEmpty) {
          final data = await compute(buildCatalogFromCacheJson, cachedJson);
          if (!data.isEmpty) {
            await _applyCatalog(data);
            unawaited(_downloadAndApplyPlaylist(silent: true));
            return;
          }
        }
      } catch (_) {
        // cache corrompido: cai para o download normal
      }
    }

    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = '';
    });
    await _downloadAndApplyPlaylist(silent: false);
  }

  /// [silent] = atualização em segundo plano: nunca mostra erro, nunca apaga
  /// sessão e só mexe na tela se a lista realmente mudou.
  Future<void> _downloadAndApplyPlaylist({required bool silent}) async {
    void fail(String msg) {
      if (silent || !mounted) return;
      setState(() {
        errorMessage = msg;
        isLoading = false;
      });
    }

    try {
      final stopwatch = Stopwatch()..start();
      final response = await http
          .get(Uri.parse(m3uUrl), headers: kIptvHeaders)
          .timeout(const Duration(seconds: 35));
      stopwatch.stop();

      if (response.statusCode == 200) {
        final bodyText = utf8.decode(response.bodyBytes, allowMalformed: true);
        if (!bodyText.contains('#EXTINF')) {
          if (silent) return;
          await AppStorage.clearSession();
          fail(
              'Nenhum canal encontrado na lista. Verifique se o Usuário e a Senha estão corretos.');
          return;
        }

        final signature = '${bodyText.length}:${bodyText.hashCode}';
        if (silent) {
          final previous = await AppStorage.loadCatalogSignature(m3uUrl);
          if (previous == signature) return; // nada mudou: zero custo de UI
        }

        if (widget.rememberSession && !silent) {
          if (isDirectM3u) {
            await AppStorage.saveVerifiedSession(
                {'mode': 'm3u', 'm3uUrl': widget.directM3uUrl});
          } else {
            await AppStorage.saveVerifiedSession({
              'mode': 'xtream',
              'dns': widget.serverDns,
              'user': widget.username,
              'pass': widget.password,
            });
          }
        }

        final bytes = response.bodyBytes.length;
        final seconds = stopwatch.elapsedMilliseconds / 1000.0;
        if (seconds > 0.1 && bytes > 10000) {
          lastMeasuredSpeedMbps =
              ((bytes * 8) / (seconds * 1000000)).clamp(1.0, 300.0);
          _engine.measuredSpeedMbps = lastMeasuredSpeedMbps;
        }

        final data = await compute(buildCatalogFromM3u, bodyText);
        if (data.isEmpty) {
          fail('A lista foi baixada, mas não contém conteúdos válidos.');
          return;
        }

        // Grava o catálogo já processado (codifica fora da thread principal)
        unawaited(() async {
          final json = await compute(encodeCatalogJson, data.all);
          await AppStorage.saveCatalogJson(m3uUrl, json, signature);
        }());

        await _applyCatalog(data, silent: silent);
      } else {
        // Só apaga a sessão quando o servidor rejeita as credenciais.
        if (!silent && (response.statusCode == 401 || response.statusCode == 403)) {
          await AppStorage.clearSession();
        }
        fail(
            'O servidor recusou a conexão (Erro ${response.statusCode}). Verifique seus dados.');
      }
    } catch (_) {
      // Falha de rede NÃO apaga mais a sessão (antes o app "deslogava" offline).
      fail('Falha de conexão com o servidor.\nVerifique o endereço DNS/URL e sua internet.');
    }
  }

  List<StreamItem> _getBaseListForSection(MainSection section) {
    switch (section) {
      case MainSection.live:
        return liveItems;
      case MainSection.movie:
        return movieItems;
      case MainSection.series:
        return seriesItems;
      case MainSection.continueWatching:
        return sortedContinueWatching.map((e) => e.item).toList();
      case MainSection.favorites:
        final favList = <StreamItem>[];
        final seenIds = <String>{};
        for (final i in allItems) {
          if (favoriteIds.contains(i.id)) {
            favList.add(i);
            seenIds.add(i.id);
          }
        }
        for (final s in allSeriesGroups) {
          if (favoriteIds.contains(s.id)) {
            final firstEp = s.allEpisodesFlat.firstOrNull;
            if (firstEp != null && !seenIds.contains(firstEp.id)) {
              favList.add(firstEp);
              seenIds.add(firstEp.id);
            }
          }
        }
        return favList;
      case MainSection.recents:
        return recentItems;
    }
  }

  String _getSectionTitle(MainSection section) {
    switch (section) {
      case MainSection.live:
        return 'TV ao Vivo';
      case MainSection.movie:
        return 'Filmes';
      case MainSection.series:
        return 'Séries';
      case MainSection.continueWatching:
        return 'Continuar Assistindo';
      case MainSection.favorites:
        return 'Meus Favoritos';
      case MainSection.recents:
        return 'Assistidos Recentemente';
    }
  }

  void _selectSection(MainSection section) {
    // Pausa silenciosamente o áudio da pré-visualização quando entra no catálogo de Séries
    if (section == MainSection.series) {
      _engine.pausePreviewSilently();
    } else if (section == MainSection.live && !isMiniPipFloating) {
      _engine.resumePreviewSilently();
    }

    setState(() {
      activeSection = section;
      selectedCategory = 'Todas';
      searchQuery = '';
      _searchController.clear();
      isTVSideMenuOpen = false;
      _rebuildSectionCategories();
    });
  }

  void _rebuildSectionCategories() {
    if (activeSection == MainSection.series) {
      final Map<String, int> counts = {'Todas': allSeriesGroups.length};
      _seriesByGroup.forEach((groupName, list) {
        counts[groupName] = list.length;
      });
      final cats = <String>['Todas', ..._seriesByGroup.keys];
      if (!cats.contains(selectedCategory)) selectedCategory = 'Todas';
      categoryCounts = counts;
      sectionCategories = cats;
      _applyCategoryAndSearchFilter();
      return;
    }

    if (activeSection == MainSection.live) {
      final Map<String, int> counts = {'Todas': liveItems.length};
      _liveByGroup.forEach((groupName, list) {
        counts[groupName] = list.length;
      });
      final cats = <String>['Todas', ..._liveByGroup.keys];
      if (!cats.contains(selectedCategory)) selectedCategory = 'Todas';
      categoryCounts = counts;
      sectionCategories = cats;
      _applyCategoryAndSearchFilter();
      return;
    }

    if (activeSection == MainSection.movie) {
      final Map<String, int> counts = {'Todas': movieItems.length};
      _movieByGroup.forEach((groupName, list) {
        counts[groupName] = list.length;
      });
      final cats = <String>['Todas', ..._movieByGroup.keys];
      if (!cats.contains(selectedCategory)) selectedCategory = 'Todas';
      categoryCounts = counts;
      sectionCategories = cats;
      _applyCategoryAndSearchFilter();
      return;
    }

    final baseList = _getBaseListForSection(activeSection);
    final Map<String, int> counts = {'Todas': baseList.length};
    for (final item in baseList) {
      counts[item.group] = (counts[item.group] ?? 0) + 1;
    }
    final cats = <String>[
      'Todas',
      ...counts.keys.where((k) => k != 'Todas'),
    ];
    if (!cats.contains(selectedCategory)) selectedCategory = 'Todas';

    categoryCounts = counts;
    sectionCategories = cats;
    _applyCategoryAndSearchFilter(baseList);
  }

  // Filtro O(1) instantâneo usando os mapas pré-indexados
  void _applyCategoryAndSearchFilter([List<StreamItem>? sourceList]) {
    if (activeSection == MainSection.series) {
      List<SeriesGroup> resSeries = selectedCategory == 'Todas'
          ? allSeriesGroups
          : (_seriesByGroup[selectedCategory] ?? const []);

      if (searchQuery.trim().isNotEmpty) {
        final q = searchQuery.toLowerCase();
        resSeries = resSeries
            .where((s) =>
                s.title.toLowerCase().contains(q) ||
                s.group.toLowerCase().contains(q))
            .toList();
      }
      setState(() => displayedSeries = resSeries);
      return;
    }

    List<StreamItem> result;
    if (activeSection == MainSection.live) {
      result = selectedCategory == 'Todas'
          ? liveItems
          : (_liveByGroup[selectedCategory] ?? const []);
    } else if (activeSection == MainSection.movie) {
      result = selectedCategory == 'Todas'
          ? movieItems
          : (_movieByGroup[selectedCategory] ?? const []);
    } else {
      final baseList = sourceList ?? _getBaseListForSection(activeSection);
      result = selectedCategory == 'Todas'
          ? baseList
          : baseList.where((i) => i.group == selectedCategory).toList();
    }

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase();
      result = result
          .where((i) =>
              i.name.toLowerCase().contains(q) ||
              i.group.toLowerCase().contains(q))
          .toList();
    }

    setState(() => displayedItems = result);
  }

  void _onSearchQueryChangedDebounced(String val) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      searchQuery = val;
      _applyCategoryAndSearchFilter();
    });
  }

  void _onCategoryTap(String category) {
    final lower = category.toLowerCase();
    final isAdultCat =
        lower.contains('adult') || lower.contains('xxx') || lower.contains('+18');

    if (isAdultCat && !adultUnlocked) {
      _promptParentalPin(() {
        setState(() {
          adultUnlocked = true;
          selectedCategory = category;
          isTVSideMenuOpen = false;
          _applyCategoryAndSearchFilter();
        });
      });
      return;
    }

    setState(() {
      selectedCategory = category;
      isTVSideMenuOpen = false;
      _applyCategoryAndSearchFilter();
    });
  }

  void _onSelectSeriesGroup(SeriesGroup series) {
    if (series.isAdult && !adultUnlocked) {
      _promptParentalPin(() {
        adultUnlocked = true;
        _onSelectSeriesGroup(series);
      });
      return;
    }

    openSeriesDetailsModal(
      context: context,
      series: series,
      vodProgressMap: vodProgressMap,
      isSeriesFavorite: favoriteIds.contains(series.id),
      onToggleSeriesFavorite: () => _toggleSeriesFavorite(series),
      seriesMetaFuture: _seriesMeta(series),
      onPlayEpisode: (episode, fullSeriesPlaylist) {
        _openFullScreen(episode, customPlaylist: fullSeriesPlaylist);
      },
      // Toque no episódio => ficha com sinopse/nota/elenco antes do play
      onEpisodeDetails: (episode, fullSeriesPlaylist) {
        _openVodDetails(episode,
            series: series, playlist: fullSeriesPlaylist);
      },
    );
  }

  // ---------------------------------------------------------------------------
  // DETALHES DE FILMES / EPISÓDIOS (sinopse, elenco, nota, ano) ANTES DO PLAY
  // ---------------------------------------------------------------------------
  Future<SeriesMetadata?> _seriesMeta(SeriesGroup s) {
    final c = _xtreamCreds;
    if (c == null) return Future.value(null);
    return _seriesMetaFutures.putIfAbsent(
      s.id,
      () => MetadataService.forSeries(
          series: s, dns: c.dns, user: c.user, pass: c.pass),
    );
  }

  SeriesGroup? _findSeriesGroupFor(StreamItem item) {
    final key = item.seriesName.trim().toLowerCase();
    for (final g in allSeriesGroups) {
      if (g.title.trim().toLowerCase() == key) return g;
    }
    return null;
  }

  Future<void> _openVodDetails(
    StreamItem item, {
    SeriesGroup? series,
    List<StreamItem>? playlist,
  }) async {
    if (item.isAdult && !adultUnlocked) {
      _promptParentalPin(() {
        adultUnlocked = true;
        _openVodDetails(item, series: series, playlist: playlist);
      });
      return;
    }

    final c = _xtreamCreds;
    Future<VodMetadata?> metaFuture;
    if (c == null) {
      metaFuture = Future.value(null);
    } else if (series != null) {
      metaFuture = _seriesMeta(series).then((sm) {
        if (sm == null) return null;
        final ep = sm.episodes[item.streamId];
        return ep == null ? sm.info : ep.mergedWith(sm.info);
      });
    } else {
      metaFuture = MetadataService.forMovie(
          item: item, dns: c.dns, user: c.user, pass: c.pass);
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      createSmoothRoute(
        VodDetailsScreen(
          item: item,
          deviceMode: currentDeviceMode,
          series: series,
          metadataFuture: metaFuture,
          progress: vodProgressMap[item.id],
          isFavorite: favoriteIds.contains(item.id),
          onToggleFavorite: () => _toggleFavorite(item),
          onPlay: (start) => _openFullScreen(
            item,
            customPlaylist: playlist,
            forcedStart: start,
          ),
        ),
      ),
    );
  }

  void _promptParentalPin(VoidCallback onSuccess) {
    final pinCtrl = TextEditingController();

    if (currentDeviceMode == DeviceMode.tv) {
      openTVVirtualKeyboard(
        context: context,
        controller: pinCtrl,
        title: 'PIN Controle Parental (Padrão: 0000)',
        isNumericOnly: true,
        onCompleted: () {
          if (pinCtrl.text == parentalPin) {
            onSuccess();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('PIN incorreto!'),
                  backgroundColor: Colors.redAccent),
            );
          }
        },
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF151924),
        title: const Text('Controle Parental'),
        content: TextField(
          controller: pinCtrl,
          keyboardType: TextInputType.number,
          obscureText: true,
          maxLength: 4,
          autofocus: true,
          decoration:
              const InputDecoration(labelText: 'Digite o PIN (Padrão: 0000)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              if (pinCtrl.text == parentalPin) {
                Navigator.pop(context);
                onSuccess();
              }
            },
            child: const Text('Desbloquear'),
          ),
        ],
      ),
    );
  }

  void _addToRecents(StreamItem item) {
    recentItems.removeWhere((r) => r.id == item.id);
    recentItems.insert(0, item);
    if (recentItems.length > 40) recentItems.removeLast();
    AppStorage.saveRecents(recentItems);
  }

  void _toggleFavorite(StreamItem item) {
    setState(() {
      if (favoriteIds.contains(item.id)) {
        favoriteIds.remove(item.id);
      } else {
        favoriteIds.add(item.id);
      }
      if (activeSection == MainSection.favorites) _rebuildSectionCategories();
    });
    AppStorage.saveFavorites(favoriteIds);
  }

  void _toggleSeriesFavorite(SeriesGroup series) {
    setState(() {
      if (favoriteIds.contains(series.id)) {
        favoriteIds.remove(series.id);
      } else {
        favoriteIds.add(series.id);
      }
      if (activeSection == MainSection.favorites) _rebuildSectionCategories();
    });
    AppStorage.saveFavorites(favoriteIds);
  }

  List<StreamItem> _findQualityVariants(StreamItem? item) {
    if (item == null || item.type != ContentType.live) {
      return item != null ? [item] : [];
    }
    final target = item.cleanName.toLowerCase();
    final variants = liveItems
        .where((i) => i.cleanName.toLowerCase() == target)
        .take(6)
        .toList();
    return variants.isEmpty ? [item] : variants;
  }

  Future<void> _startPreview(StreamItem item,
      {bool forcePreviewOnly = false}) async {
    if (item.isAdult && !adultUnlocked) {
      _promptParentalPin(() {
        adultUnlocked = true;
        _startPreview(item, forcePreviewOnly: forcePreviewOnly);
      });
      return;
    }

    // Filmes e séries: ficha completa (sinopse, nota, elenco) antes de dar play.
    if (!forcePreviewOnly && item.type != ContentType.live) {
      if (item.type == ContentType.series) {
        final group = _findSeriesGroupFor(item);
        if (group != null) {
          _onSelectSeriesGroup(group);
          return;
        }
      }
      _openVodDetails(item);
      return;
    }

    _addToRecents(item);

    // 1º Clique = Pré-visualização | 2º Clique = Expande em Tela Cheia sem reiniciar o fluxo
    if (!forcePreviewOnly && _engine.currentItem?.id == item.id) {
      _openFullScreen(item);
      return;
    }

    final savedEntry = vodProgressMap[item.id];
    final resumeDur = (savedEntry != null && item.type != ContentType.live)
        ? Duration(seconds: savedEntry.positionSeconds)
        : null;

    await _engine.openStream(item, startPosition: resumeDur);
  }

  Future<void> _openFullScreen(StreamItem item,
      {List<StreamItem>? customPlaylist, Duration? forcedStart}) async {
    if (accountStatus.blocksAccess) return;
    if (item.isAdult && !adultUnlocked) {
      _promptParentalPin(() {
        adultUnlocked = true;
        _openFullScreen(item,
            customPlaylist: customPlaylist, forcedStart: forcedStart);
      });
      return;
    }

    _addToRecents(item);

    Duration? chosenStartPos;
    final savedEntry = vodProgressMap[item.id];

    if (forcedStart != null) {
      chosenStartPos = forcedStart;
    } else if (item.type != ContentType.live &&
        savedEntry != null &&
        _engine.currentItem?.id != item.id) {
      final decision = await showVodResumePrompt(
        context: context,
        entry: savedEntry,
      );
      if (decision == null) return;
      chosenStartPos = decision;
    }

    if (!mounted) return;
    final targetPlaylist = customPlaylist ??
        (displayedItems.isNotEmpty ? displayedItems : liveItems);

    Navigator.push(
      context,
      createSmoothRoute(
        SmartAdaptivePlayerScreen(
          deviceMode: currentDeviceMode,
          initialItem: item,
          playlist: targetPlaylist,
          liveChannelsPool: liveItems,
          measuredSpeedMbps: lastMeasuredSpeedMbps,
          initialStartPosition: chosenStartPos,
          favoriteIds: favoriteIds,
          onToggleFavorite: _toggleFavorite,
          onMinimizeToPip: (playingItem) {
            setState(() => isMiniPipFloating = true);
            _engine.openStream(playingItem);
          },
        ),
      ),
    );
  }

  void _showSpeedTestModal() {
    showDialog(
      context: context,
      builder: (_) => SpeedTestDialog(
        testUrl: m3uUrl,
        onSpeedMeasured: (mbps) {
          setState(() => lastMeasuredSpeedMbps = mbps);
          _engine.measuredSpeedMbps = mbps;
        },
      ),
    );
  }

  void _handleDashboardBackButton() {
    if (searchQuery.isNotEmpty) {
      setState(() {
        searchQuery = '';
        _searchController.clear();
        _applyCategoryAndSearchFilter();
      });
      return;
    }

    if (currentDeviceMode == DeviceMode.tv) {
      if (!isTVSideMenuOpen) {
        setState(() => isTVSideMenuOpen = true);
        return;
      }
    } else {
      final isDrawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
      if (!isDrawerOpen) {
        _scaffoldKey.currentState?.openDrawer();
        return;
      } else {
        Navigator.pop(context);
      }
    }

    showExitAppConfirmationDialog(context);
  }

  Widget _buildMiniVideoWidget() {
    if (_engine.hasError) {
      return const Center(
        child: Text('Sinal indisponível',
            style: TextStyle(fontSize: 11, color: Colors.white54)),
      );
    }
    if (!_engine.isReady || _engine.controller == null) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
      );
    }
    final ctrl = _engine.controller!;
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: ctrl.value.size.width,
        height: ctrl.value.size.height,
        child: VideoPlayer(ctrl),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isTVMode = currentDeviceMode == DeviceMode.tv;
    final activeItem = _engine.currentItem;
    final activeEpg = _engine.currentEpg;
    final cwEntries = sortedContinueWatching;

    final mobileView = MobileDashboardView(
      scaffoldKey: _scaffoldKey,
      activeSection: activeSection,
      sectionTitle: _getSectionTitle(activeSection),
      selectedCategory: selectedCategory,
      sectionCategories: sectionCategories,
      categoryCounts: categoryCounts,
      totalAllCount: allItems.length,
      liveCount: liveItems.length,
      movieCount: movieItems.length,
      seriesCount: allSeriesGroups.length,
      continueWatchingCount: cwEntries.length,
      favoritesCount: favoriteIds.length,
      recentsCount: recentItems.length,
      accountExpDate: accountExpDate,
      displayedItems: displayedItems,
      displayedSeries: displayedSeries,
      continueWatchingEntries: cwEntries,
      vodProgressMap: vodProgressMap,
      favoriteIds: favoriteIds,
      activeItem: activeItem,
      activeEpg: activeEpg,
      isMiniPipFloating: isMiniPipFloating,
      miniVideoWidget: _buildMiniVideoWidget(),
      searchController: _searchController,
      searchQuery: searchQuery,
      onSelectSection: _selectSection,
      onSelectCategory: _onCategoryTap,
      onSearchChanged: _onSearchQueryChangedDebounced,
      onClearSearch: () {
        _searchDebounce?.cancel();
        _searchController.clear();
        searchQuery = '';
        _applyCategoryAndSearchFilter();
      },
      onStartPreview: _startPreview,
      onOpenFullScreen: _openFullScreen,
      onSelectSeriesGroup: _onSelectSeriesGroup,
      onToggleFavorite: _toggleFavorite,
      onEnableMiniPip: () => setState(() => isMiniPipFloating = true),
      onOpenSpeedTest: _showSpeedTestModal,
      onRefreshPlaylist: () => _loadAccountInfoAndPlaylist(forceNetwork: true),
      onSwitchToTVMode: _switchDeviceMode,
      onLogout: () => _returnToLoginForEditing(),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleDashboardBackButton();
      },
      child: Scaffold(
        key: _scaffoldKey,
        drawerEdgeDragWidth: 56,
        drawer: (isTVMode || accountStatus.blocksAccess)
            ? null
            : mobileView.buildDrawer(context),
        body: SafeArea(
          child: Stack(
            children: [
              accountStatus.blocksAccess
                  ? _buildAccountBlockedState()
                  : isLoading
                  ? _buildLoadingState()
                  : errorMessage.isNotEmpty
                      ? _buildErrorState()
                      : isTVMode
                          ? TVDashboardView(
                              isSideMenuOpen: isTVSideMenuOpen,
                              onOpenSideMenu: () =>
                                  setState(() => isTVSideMenuOpen = true),
                              onCloseSideMenu: () =>
                                  setState(() => isTVSideMenuOpen = false),
                              activeSection: activeSection,
                              sectionTitle: _getSectionTitle(activeSection),
                              selectedCategory: selectedCategory,
                              sectionCategories: sectionCategories,
                              categoryCounts: categoryCounts,
                              totalAllCount: allItems.length,
                              liveCount: liveItems.length,
                              movieCount: movieItems.length,
                              seriesCount: allSeriesGroups.length,
                              continueWatchingCount: cwEntries.length,
                              favoritesCount: favoriteIds.length,
                              recentsCount: recentItems.length,
                              displayedItems: displayedItems,
                              displayedSeries: displayedSeries,
                              vodProgressMap: vodProgressMap,
                              favoriteIds: favoriteIds,
                              activeItem: activeItem,
                              activeEpg: activeEpg,
                              activeQualityVariants:
                                  _findQualityVariants(activeItem),
                              miniVideoWidget: _buildMiniVideoWidget(),
                              searchController: _searchController,
                              searchQuery: searchQuery,
                              onSelectSection: _selectSection,
                              onSelectCategory: _onCategoryTap,
                              onSearchChanged: _onSearchQueryChangedDebounced,
                              onClearSearch: () {
                                _searchDebounce?.cancel();
                                setState(() {
                                  searchQuery = '';
                                  _searchController.clear();
                                  _applyCategoryAndSearchFilter();
                                });
                              },
                              onStartPreview: _startPreview,
                              onOpenFullScreen: _openFullScreen,
                              onSelectSeriesGroup: _onSelectSeriesGroup,
                              onToggleFavorite: _toggleFavorite,
                              onToggleSeriesFavorite: _toggleSeriesFavorite,
                              onOpenSpeedTest: _showSpeedTestModal,
                              onRefreshPlaylist: () =>
                                  _loadAccountInfoAndPlaylist(
                                      forceNetwork: true),
                              onSwitchToMobileMode: _switchDeviceMode,
                              onLogout: () => _returnToLoginForEditing(),
                            )
                          : mobileView,
              if (isMiniPipFloating && activeItem != null)
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Material(
                    elevation: 16,
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF12151F),
                    child: Container(
                      width: isTVMode ? 300 : 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: const Color(0xFF00E5FF), width: 1.5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AspectRatio(
                            aspectRatio: 16 / 9,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(13)),
                              child: Container(
                                color: Colors.black,
                                child: _buildMiniVideoWidget(),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    activeItem.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                TVIconButton(
                                  icon: Icons.open_in_full_rounded,
                                  size: 16,
                                  color: const Color(0xFF00E5FF),
                                  onPressed: () {
                                    setState(() => isMiniPipFloating = false);
                                    _openFullScreen(activeItem);
                                  },
                                ),
                                TVIconButton(
                                  icon: Icons.close_rounded,
                                  size: 16,
                                  onPressed: () {
                                    _engine.pausePreviewSilently();
                                    setState(() => isMiniPipFloating = false);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAccountBlockedState() {
    final st = accountStatus;
    final isExpired = st.state == AccountState.expired;
    final color = isExpired ? Colors.orangeAccent : Colors.redAccent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Container(
            padding: const EdgeInsets.all(26),
            decoration: BoxDecoration(
              color: const Color(0xFF12151F),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: color.withOpacity(0.55), width: 1.4),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isExpired
                      ? Icons.event_busy_rounded
                      : Icons.block_rounded,
                  color: color,
                  size: 56,
                ),
                const SizedBox(height: 14),
                Text(
                  isExpired ? 'Assinatura vencida' : 'Acesso indisponível',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(
                  st.friendlyMessage,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 14, color: Colors.white70, height: 1.4),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Entre em contato com o seu provedor para renovar ou regularizar o acesso. '
                  'Depois de renovar, toque em "Verificar novamente".',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: Colors.white54, height: 1.4),
                ),
                const SizedBox(height: 22),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.center,
                  children: [
                    TVFocusableItem(
                      autofocus: true,
                      autoScroll: false,
                      onSelect: _recheckBlockedAccount,
                      builder: (context, isFocused) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused ? Colors.white : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: _checkingAccountAgain
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black),
                              )
                            : const Text(
                                'VERIFICAR NOVAMENTE',
                                style: TextStyle(
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12),
                              ),
                      ),
                    ),
                    TVFocusableItem(
                      autoScroll: false,
                      onSelect: () => _returnToLoginForEditing(),
                      builder: (context, isFocused) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF151924),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isFocused
                                ? const Color(0xFF00E5FF)
                                : Colors.white24,
                          ),
                        ),
                        child: const Text('Trocar lista / Sair',
                            style: TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF00E5FF)),
          const SizedBox(height: 18),
          const Text('SINCRONIZANDO CATÁLOGO, SÉRIES E EPG...'),
          const SizedBox(height: 20),
          TVFocusableItem(
            autofocus: true,
            autoScroll: false,
            onSelect: () => _returnToLoginForEditing(),
            builder: (context, isFocused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF151924),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isFocused ? const Color(0xFF00E5FF) : Colors.white24,
                ),
              ),
              child: const Text('Cancelar e Voltar ao Login',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: Colors.redAccent, size: 50),
              const SizedBox(height: 14),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                alignment: WrapAlignment.center,
                children: [
                  TVFocusableItem(
                    autofocus: true,
                    autoScroll: false,
                    onSelect: () => _returnToLoginForEditing(
                      errorBanner:
                          'Corrija os dados de acesso abaixo e tente novamente.',
                    ),
                    builder: (context, isFocused) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFF00E5FF), Color(0xFF2979FF)]),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused ? Colors.white : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: const Text(
                        'CORRIGIR DADOS DE LOGIN',
                        style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w900,
                            fontSize: 12),
                      ),
                    ),
                  ),
                  TVFocusableItem(
                    autoScroll: false,
                    onSelect: () =>
                        _loadAccountInfoAndPlaylist(forceNetwork: true),
                    builder: (context, isFocused) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151924),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isFocused
                              ? const Color(0xFF00E5FF)
                              : Colors.white24,
                        ),
                      ),
                      child: const Text('Tentar Novamente',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
