import 'package:flutter/widgets.dart';

import 'app/mobile_app_services.dart';
import 'ui/echat_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await MobileAppServices.bootstrap();
  runApp(EchatApp(services: services));
}
