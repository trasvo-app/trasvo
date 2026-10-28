// This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0.
// If a copy of the MPL was not distributed with this file, You can obtain one at https://mozilla.org/MPL/2.0/.

import 'package:flutter/material.dart';

import 'core/di/app_scope.dart';
import 'core/theme/app_theme.dart';
import 'features/connect/presentation/link_request_listener.dart';
import 'features/home/presentation/home_page.dart';
import 'features/onboarding/presentation/theme_choice_page.dart';
import 'features/transfers/presentation/offer_listener.dart';

class App extends StatefulWidget {
  const App({super.key, required this.services});

  final AppServices services;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    final theme = widget.services.theme;
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: theme,
        builder: (context, _) => MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Trasvo',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: theme.mode,
          // Sin animación al cambiar de tema.
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => LinkRequestListener(
            connection: widget.services.connection,
            navigatorKey: _navigatorKey,
            child: OfferListener(
              transfers: widget.services.transfers,
              navigatorKey: _navigatorKey,
              child: child!,
            ),
          ),
          home: theme.hasChosen ? const HomePage() : ThemeChoicePage(controller: theme),
        ),
      ),
    );
  }
}
