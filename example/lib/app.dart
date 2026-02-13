import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/session/session_controller.dart';
import 'features/session/session_screen.dart';
import 'features/trace_tools/trace_controller.dart';
import 'features/trace_tools/trace_screen.dart';
import 'services/sensors/imu_feed.dart';
import 'services/sensors/location_feed.dart';
import 'services/storage/file_exporter.dart';
import 'services/storage/trace_store.dart';
import 'services/sensors/barometer_feed.dart';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<LocationFeed>(create: (_) => LocationFeed()),
        Provider<ImuFeed>(create: (_) => ImuFeed()),
        Provider<BarometerFeed>(create: (_) => BarometerFeed()),
        Provider<FileExporter>(create: (_) => FileExporter()),
        ChangeNotifierProvider<TraceStore>(create: (_) => TraceStore()),
        ChangeNotifierProvider<SessionController>(
          create: (ctx) => SessionController(
            locationFeed: ctx.read<LocationFeed>(),
            imuFeed: ctx.read<ImuFeed>(),
            barometerFeed: ctx.read<BarometerFeed>(), // ✅ add this
            traceStore: ctx.read<TraceStore>(),
            fileExporter: ctx.read<FileExporter>(),
          ),
        ),
        ChangeNotifierProvider<TraceController>(
          create: (ctx) => TraceController(
            traceStore: ctx.read<TraceStore>(),
            fileExporter: ctx.read<FileExporter>(),
          ),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.system,
        routes: {
          '/': (_) => const HomeScreen(),
          '/session': (_) => const SessionScreen(),
          '/trace': (_) => const TraceScreen(),
        },
      ),
    );
  }
}
