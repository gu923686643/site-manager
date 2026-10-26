import 'package:flutter_test/flutter_test.dart';
import 'package:site_manager/services/site_import.dart';

void main() {
  group('parseImportLine', () {
    test('逗号分隔', () {
      final e = parseImportLine('Future Hub,https://api.futureppo.top')!;
      expect(e.name, 'Future Hub');
      expect(e.baseUrl, 'https://api.futureppo.top');
    });

    test('中文逗号与制表符分隔', () {
      expect(parseImportLine('华为云，https://115.175.46.250')!.name, '华为云');
      expect(parseImportLine('站\t http://a.example.com ')!.baseUrl,
          'http://a.example.com');
    });

    test('空白分隔，名称可含空格（地址在最后）', () {
      final e = parseImportLine('Future Hub https://api.futureppo.top')!;
      expect(e.name, 'Future Hub');
      expect(e.baseUrl, 'https://api.futureppo.top');
    });

    test('只有地址时名称取域名', () {
      final e = parseImportLine('https://api.example.com/')!;
      expect(e.name, 'api.example.com');
      expect(e.baseUrl, 'https://api.example.com/');
    });

    test('缺 scheme 自动补 https', () {
      final e = parseImportLine('我的站 api.example.com')!;
      expect(e.baseUrl, 'https://api.example.com');
    });

    test('非法行返回 null', () {
      expect(parseImportLine('只有名字没有地址'), isNull);
      expect(parseImportLine('站,notaurl'), isNull);
      expect(parseImportLine('站,'), isNull);
    });

    test('名称为空时用域名补齐，不算非法', () {
      final e = parseImportLine(',https://a.example.com')!;
      expect(e.name, 'a.example.com');
    });
  });

  group('parseImportText', () {
    test('空行与注释行跳过，无效行收集', () {
      final r = parseImportText('''
# 注释
站一,https://a.example.com

站二 https://b.example.com
坏行没有地址
''');
      expect(r.entries.map((e) => e.name), ['站一', '站二']);
      expect(r.invalidLines, ['坏行没有地址']);
    });
  });
}
