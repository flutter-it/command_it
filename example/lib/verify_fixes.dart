import 'package:command_it/command_it.dart';

class Test {
  final cmd = Command.createAsyncNoParamNoResult(() async {});

  void test() {
    cmd.execute();
    cmd.executeWithFuture();
  }
}
