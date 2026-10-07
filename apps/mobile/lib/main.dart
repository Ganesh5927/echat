import 'package:flutter/material.dart';

import 'app/mobile_app_services.dart';
import 'ui/echat_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _AppBootstrapper());
}

class _AppBootstrapper extends StatefulWidget {
  const _AppBootstrapper();

  @override
  State<_AppBootstrapper> createState() => _AppBootstrapperState();
}

class _AppBootstrapperState extends State<_AppBootstrapper> {
  late final Future<MobileAppServices> _bootstrapFuture =
      MobileAppServices.bootstrap();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MobileAppServices>(
      future: _bootstrapFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const MaterialApp(
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Starting eChat…'),
                  ],
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return const MaterialApp(
            title: 'eChat',
            home: Scaffold(
              body: Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'eChat could not initialize. Restart the app, and check device storage if the problem continues.',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          );
        }
        return EchatApp(services: snapshot.data!);
      },
    );
  }
}
