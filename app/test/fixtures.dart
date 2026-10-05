import 'dart:convert';
import 'dart:io';

/// Fixtures are produced from the real gateway and database by
/// `MAKE_FIXTURES=1 tools/db/integration.sh`, so these tests check the app against exactly
/// what the server sends.
dynamic fixture(String name) => jsonDecode(File('test/fixtures/$name.json').readAsStringSync());
