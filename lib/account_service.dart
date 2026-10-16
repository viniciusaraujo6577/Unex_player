import 'dart:convert';
import 'package:http/http.dart' as http;

import 'core.dart';

enum AccountState { active, expired, disabled, authFailed, unknown }

/// Resultado da validação da conta Xtream Codes.
class AccountStatus {
  final AccountState state;
  final DateTime? expiresAt; // null = sem vencimento (ou desconhecido)
  final bool isTrial;
  final int maxConnections;
  final int activeConnections;
  final bool fromCache;

  const AccountStatus({
    required this.state,
    this.expiresAt,
    this.isTrial = false,
    this.maxConnections = 0,
    this.activeConnections = 0,
    this.fromCache = false,
  });

  static const unknown = AccountStatus(state: AccountState.unknown);

  /// Só bloqueia quando temos CERTEZA (nunca bloqueia por falha de rede).
  bool get blocksAccess =>
      state == AccountState.expired ||
      state == AccountState.disabled ||
      state == AccountState.authFailed;

  int? get daysLeft {
    final e = expiresAt;
    if (e == null) return null;
    final diff = e.difference(DateTime.now());
    if (diff.isNegative) return 0;
    return (diff.inHours / 24).ceil();
  }

  bool get expiresSoon {
    final d = daysLeft;
    return state == AccountState.active && d != null && d <= 3;
  }

  String get formattedExpiry {
    final dt = expiresAt;
    if (dt == null) return '';
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String get friendlyMessage {
    switch (state) {
      case AccountState.expired:
        final d = formattedExpiry;
        return d.isEmpty
            ? 'Sua assinatura venceu.'
            : 'Sua assinatura venceu em $d.';
      case AccountState.disabled:
        return 'Sua conta está desativada ou bloqueada pelo provedor.';
      case AccountState.authFailed:
        return 'Usuário ou senha inválidos para este servidor.';
      default:
        return '';
    }
  }

  Map<String, dynamic> toJson() => {
        'state': state.index,
        'expiresAtMs': expiresAt?.millisecondsSinceEpoch,
        'isTrial': isTrial,
        'maxConnections': maxConnections,
        'activeConnections': activeConnections,
      };

  factory AccountStatus.fromJson(Map<String, dynamic> j, {bool fromCache = true}) {
    final idx = (j['state'] as int?) ?? AccountState.unknown.index;
    final ms = j['expiresAtMs'] as int?;
    return AccountStatus(
      state: AccountState.values[idx.clamp(0, AccountState.values.length - 1)],
      expiresAt: ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
      isTrial: j['isTrial'] == true,
      maxConnections: (j['maxConnections'] as int?) ?? 0,
      activeConnections: (j['activeConnections'] as int?) ?? 0,
      fromCache: fromCache,
    );
  }
}

class AccountService {
  AccountService._();

  /// Se o link M3U for do tipo get.php?username=..&password=.., extrai as
  /// credenciais Xtream para também validar o vencimento nesse modo.
  static ({String dns, String user, String pass})? credentialsFromM3u(
      String m3uUrl) {
    try {
      final uri = Uri.parse(m3uUrl);
      final user = uri.queryParameters['username'];
      final pass = uri.queryParameters['password'];
      if (user == null || pass == null || user.isEmpty || pass.isEmpty) {
        return null;
      }
      if (!uri.path.toLowerCase().contains('get.php')) return null;
      final dns =
          '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
      return (dns: dns, user: user, pass: pass);
    } catch (_) {
      return null;
    }
  }

  /// Valida online. Em falha de rede retorna [AccountStatus.unknown].
  static Future<AccountStatus> check({
    required String dns,
    required String user,
    required String pass,
  }) async {
    try {
      final uri = Uri.parse(
          '$dns/player_api.php?username=${Uri.encodeQueryComponent(user)}&password=${Uri.encodeQueryComponent(pass)}');
      final res = await http
          .get(uri, headers: kIptvHeaders)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return AccountStatus.unknown;

      final data = jsonDecode(utf8.decode(res.bodyBytes, allowMalformed: true));
      if (data is! Map) return AccountStatus.unknown;
      final info = data['user_info'];
      if (info is! Map) return AccountStatus.unknown;

      final auth = info['auth']?.toString();
      if (auth == '0') {
        return const AccountStatus(state: AccountState.authFailed);
      }

      final status = (info['status']?.toString() ?? '').toLowerCase();
      final expRaw = info['exp_date']?.toString();
      final expSec = int.tryParse(expRaw ?? '');
      final expiresAt = (expSec != null && expSec > 0)
          ? DateTime.fromMillisecondsSinceEpoch(expSec * 1000)
          : null;

      AccountState state = AccountState.active;
      if (status == 'disabled' || status == 'banned') {
        state = AccountState.disabled;
      } else if (status == 'expired' ||
          (expiresAt != null && expiresAt.isBefore(DateTime.now()))) {
        state = AccountState.expired;
      }

      final result = AccountStatus(
        state: state,
        expiresAt: expiresAt,
        isTrial: info['is_trial']?.toString() == '1',
        maxConnections: int.tryParse(info['max_connections']?.toString() ?? '') ?? 0,
        activeConnections: int.tryParse(info['active_cons']?.toString() ?? '') ?? 0,
      );
      await AppStorage.saveAccountStatus(result.toJson());
      return result;
    } catch (_) {
      return AccountStatus.unknown;
    }
  }

  /// Último estado conhecido (vale mesmo offline). Reavalia a data de
  /// vencimento com o relógio atual.
  static Future<AccountStatus> cached() async {
    final j = await AppStorage.loadAccountStatus();
    if (j == null) return AccountStatus.unknown;
    final s = AccountStatus.fromJson(j);
    if (s.state == AccountState.active &&
        s.expiresAt != null &&
        s.expiresAt!.isBefore(DateTime.now())) {
      return AccountStatus(
        state: AccountState.expired,
        expiresAt: s.expiresAt,
        isTrial: s.isTrial,
        maxConnections: s.maxConnections,
        activeConnections: s.activeConnections,
        fromCache: true,
      );
    }
    return s;
  }
}
