import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/screens/linux_do_login_screen.dart';

void main() {
  group('linuxDoSettled', () {
    test('linux.do 主域名判定为已回到本站', () {
      expect(linuxDoSettled(Uri.parse('https://linux.do/')), true);
      expect(linuxDoSettled(Uri.parse('https://linux.do/login')), true);
      expect(
          linuxDoSettled(Uri.parse('https://linux.do/auth/github/callback')),
          true);
    });

    test('linux.do 子域名判定为已回到本站', () {
      expect(
          linuxDoSettled(Uri.parse('https://connect.linux.do/callback')),
          true);
    });

    test('GitHub 等 OAuth 中转页不判定（关键：防跳转中误 pop）', () {
      expect(
          linuxDoSettled(
              Uri.parse('https://github.com/login/oauth/authorize')),
          false);
      expect(linuxDoSettled(Uri.parse('https://github.com/')), false);
    });

    test('形似的钓鱼域名不判定', () {
      expect(linuxDoSettled(Uri.parse('https://fakelinux.do/')), false);
      expect(
          linuxDoSettled(Uri.parse('https://linux.do.evil.com/')), false);
    });

    test('空 URL 不判定', () {
      expect(linuxDoSettled(null), false);
    });

    test('大小写不敏感', () {
      expect(linuxDoSettled(Uri.parse('https://LINUX.DO/')), true);
    });
  });
}
