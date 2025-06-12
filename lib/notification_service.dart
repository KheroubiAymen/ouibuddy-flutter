import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io'; // AJOUTÉ pour Platform.isIOS

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    print('🔔 Initialisation des notifications système...');

    // Configuration Android
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuration iOS améliorée
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      requestCriticalPermission: false, // MODIFIÉ : Critical peut causer des problèmes
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
      onDidReceiveLocalNotification: onDidReceiveLocalNotification, // AJOUTÉ pour iOS ancien
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    // Initialiser le plugin
    await _notifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse details) {
        print('🔔 Notification cliquée: ${details.payload}');
        _handleNotificationClick(details);
      },
    );

    // Demander les permissions
    await _requestPermissions();

    // Créer le canal de notification pour Android
    await _createNotificationChannel();

    print('✅ Notifications système initialisées');
  }

  // NOUVEAU : Callback pour iOS versions anciennes
  static void onDidReceiveLocalNotification(
      int id,
      String? title,
      String? body,
      String? payload,
      ) async {
    print('📱 [iOS] Notification reçue: $title');
  }

  // MODIFIÉE : Demander les permissions avec gestion iOS/Android séparée
  static Future<void> _requestPermissions() async {
    print('🔐 Demande des permissions notifications...');

    try {
      if (Platform.isAndroid) {
        // Permission Android
        if (await Permission.notification.isDenied) {
          final result = await Permission.notification.request();
          print('📱 Permission Android: $result');
        }
      } else if (Platform.isIOS) {
        // Permissions iOS spécifiques
        print('🍎 [iOS] Demande permissions spécifiques...');
        final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosImplementation != null) {
          final bool? granted = await iosImplementation.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
            critical: false, // MODIFIÉ : Éviter critical sur iOS
          );
          print('📱 Permissions iOS accordées: $granted');
        }
      }

      // Vérifier le statut final
      final status = await Permission.notification.status;
      print('📊 Statut final permission notification: $status');
    } catch (e) {
      print('❌ Erreur demande permissions: $e');
    }
  }

  // NOUVELLE MÉTHODE : Demander explicitement les permissions iOS
  static Future<bool> requestPermissions() async {
    if (!Platform.isIOS) {
      return await areNotificationsEnabled();
    }

    try {
      print('📱 [iOS] Demande explicite de permissions...');

      final IOSFlutterLocalNotificationsPlugin? iosImplementation =
      _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iosImplementation != null) {
        final bool? result = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: false,
        );

        print('📱 [iOS] Résultat permissions: $result');
        return result ?? false;
      }

      return false;
    } catch (e) {
      print('❌ [iOS] Erreur demande permissions: $e');
      return false;
    }
  }

  // MODIFIÉE : Vérifier les permissions avec plus de détails sur iOS
  static Future<bool> areNotificationsEnabled() async {
    try {
      if (Platform.isIOS) {
        final IOSFlutterLocalNotificationsPlugin? iosImplementation =
        _notifications.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();

        if (iosImplementation != null) {
          final NotificationsEnabledOptions? result = await iosImplementation.checkPermissions();
          print('📱 [iOS] Permissions vérifiées: $result');
          // Vérifier si au moins les alertes sont autorisées
          return result?.isEnabled ?? false;
        }
        return false;
      } else {
        // Android - logique existante
        final status = await Permission.notification.status;
        print('📋 [Android] Statut notifications: $status');
        return status == PermissionStatus.granted;
      }
    } catch (e) {
      print('❌ Erreur vérification permissions: $e');
      return false;
    }
  }

  // Créer un canal de notification pour Android
  static Future<void> _createNotificationChannel() async {
    if (!Platform.isAndroid) return;

    try {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'ouibuddy_high_importance',
        'OuiBuddy Notifications',
        description: 'Notifications importantes de l\'application OuiBuddy',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
        showBadge: true,
      );

      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
      _notifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (androidImplementation != null) {
        await androidImplementation.createNotificationChannel(channel);
        print('📺 Canal notification Android créé');
      }
    } catch (e) {
      print('❌ Erreur création canal Android: $e');
    }
  }

  // MODIFIÉE : Afficher notification de bienvenue avec gestion iOS
  static Future<void> showWelcomeNotification(String firstName, int userId) async {
    print('📱 [${Platform.isIOS ? "iOS" : "Android"}] Envoi notification système de bienvenue...');

    try {
      // Vérifier les permissions d'abord
      final enabled = await areNotificationsEnabled();
      if (!enabled) {
        print('❌ Notifications non autorisées - tentative d\'activation...');

        if (Platform.isIOS) {
          final granted = await requestPermissions();
          if (!granted) {
            print('❌ [iOS] Permissions refusées');
            return;
          }
        } else {
          print('❌ [Android] Permissions manquantes');
          return;
        }
      }

      // Créer les détails de notification adaptés à la plateforme
      final NotificationDetails notificationDetails = NotificationDetails(
        android: Platform.isAndroid ? AndroidNotificationDetails(
          'ouibuddy_high_importance',
          'OuiBuddy Notifications',
          channelDescription: 'Notifications importantes de l\'application OuiBuddy',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Colors.blue,
          enableVibration: true,
          playSound: true,
          showWhen: true,
          styleInformation: BigTextStyleInformation(
            'Bienvenue sur OuiBuddy ! Vous êtes maintenant connecté avec succès et sur votre dashboard.',
            summaryText: 'OuiBuddy',
            contentTitle: '👋 Salut $firstName !',
          ),
        ) : null,
        iOS: Platform.isIOS ? DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          badgeNumber: 1,
          subtitle: 'Connexion réussie',
          threadIdentifier: 'ouibuddy_welcome',
          interruptionLevel: InterruptionLevel.active,
        ) : null,
      );

      await _notifications.show(
        userId,
        '👋 Salut $firstName !',
        'Connexion réussie ! Vous êtes sur votre dashboard OuiBuddy.',
        notificationDetails,
        payload: 'welcome_$userId',
      );

      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Notification système de bienvenue envoyée avec succès');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur envoi notification de bienvenue: $e');
    }
  }

  // MODIFIÉE : Afficher notification personnalisée avec gestion iOS
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool isImportant = false,
  }) async {
    print('📱 [${Platform.isIOS ? "iOS" : "Android"}] Envoi notification système personnalisée...');

    try {
      final NotificationDetails notificationDetails = NotificationDetails(
        android: Platform.isAndroid ? AndroidNotificationDetails(
          'ouibuddy_high_importance',
          'OuiBuddy Notifications',
          channelDescription: 'Notifications importantes de l\'application OuiBuddy',
          importance: isImportant ? Importance.max : Importance.high,
          priority: isImportant ? Priority.max : Priority.high,
          icon: '@mipmap/ic_launcher',
          color: Colors.blue,
          enableVibration: true,
          playSound: true,
          showWhen: true,
          styleInformation: BigTextStyleInformation(
            body,
            summaryText: 'OuiBuddy',
            contentTitle: title,
          ),
        ) : null,
        iOS: Platform.isIOS ? DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          subtitle: 'OuiBuddy',
          threadIdentifier: 'ouibuddy_general',
          interruptionLevel: isImportant
              ? InterruptionLevel.timeSensitive  // MODIFIÉ : timeSensitive au lieu de critical
              : InterruptionLevel.active,
        ) : null,
      );

      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Notification système personnalisée envoyée');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur envoi notification personnalisée: $e');
    }
  }

  // MODIFIÉE : Notification de test simple avec gestion iOS
  static Future<void> showTestNotification(String firstName) async {
    print('🧪 [${Platform.isIOS ? "iOS" : "Android"}] Envoi notification de test...');

    try {
      await showNotification(
        id: 999,
        title: '🧪 Test OuiBuddy ${Platform.isIOS ? "🍎" : "🤖"}',
        body: 'Notification de test pour $firstName - Tout fonctionne sur ${Platform.isIOS ? "iOS" : "Android"} !',
        payload: 'test_notification',
        isImportant: false,
      );

      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Notification de test envoyée');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur notification de test: $e');
    }
  }

  // Notification importante (urgente)
  static Future<void> showImportantNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    print('🚨 [${Platform.isIOS ? "iOS" : "Android"}] Envoi notification importante...');

    try {
      await showNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
        isImportant: true,
      );

      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Notification importante envoyée');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur notification importante: $e');
    }
  }

  // MODIFIÉE : Test spécifique iOS
  static Future<void> testIOSNotifications(String userName) async {
    if (!Platform.isIOS) return;

    try {
      print('📱 [iOS] Test spécifique des notifications...');

      // Demander les permissions d'abord
      final bool granted = await requestPermissions();

      if (!granted) {
        print('❌ [iOS] Permissions non accordées');
        return;
      }

      // Envoyer une notification de test
      await showNotification(
        id: 998,
        title: '🧪 [iOS] Test Notification',
        body: 'Bonjour $userName ! Les notifications fonctionnent sur iOS 📱',
        payload: 'ios_test',
      );

      print('✅ [iOS] Notification de test envoyée');

    } catch (e) {
      print('❌ [iOS] Erreur test notifications: $e');
    }
  }

  // Gérer le clic sur notification
  static void _handleNotificationClick(NotificationResponse details) {
    print('🔔 [${Platform.isIOS ? "iOS" : "Android"}] Notification cliquée: ${details.payload}');

    try {
      if (details.payload?.startsWith('welcome_') == true) {
        print('👋 Notification de bienvenue cliquée');
        // Ici vous pouvez naviguer vers une page spécifique
      } else if (details.payload == 'test_notification') {
        print('🧪 Notification de test cliquée');
      } else if (details.payload == 'ios_test') {
        print('🍎 Notification de test iOS cliquée');
      } else if (details.payload?.startsWith('scheduled_') == true) {
        print('⏰ Notification programmée cliquée');
      }
    } catch (e) {
      print('❌ Erreur gestion clic notification: $e');
    }
  }

  // MODIFIÉE : Ouvrir les paramètres avec gestion iOS
  static Future<void> openNotificationSettings() async {
    try {
      print('🔧 [${Platform.isIOS ? "iOS" : "Android"}] Ouverture des paramètres de l\'app...');

      if (Platform.isIOS) {
        // Sur iOS, on ne peut pas ouvrir directement les paramètres de notifications
        // Mais on peut essayer d'ouvrir les paramètres de l'app
        await openAppSettings();
        print('🍎 [iOS] Paramètres de l\'app ouverts (l\'utilisateur doit naviguer vers Notifications)');
      } else {
        await openAppSettings();
        print('🤖 [Android] Paramètres ouverts');
      }
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur ouverture paramètres: $e');
    }
  }

  // Annuler une notification spécifique
  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Notification $id annulée');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur annulation notification $id: $e');
    }
  }

  // Annuler toutes les notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      print('✅ [${Platform.isIOS ? "iOS" : "Android"}] Toutes les notifications annulées');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur annulation toutes notifications: $e');
    }
  }

  // Obtenir toutes les notifications en attente
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      final pending = await _notifications.pendingNotificationRequests();
      print('📋 [${Platform.isIOS ? "iOS" : "Android"}] ${pending.length} notifications en attente');
      return pending;
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur récupération notifications en attente: $e');
      return [];
    }
  }

  // MODIFIÉE : Méthode utilitaire pour tester toutes les fonctionnalités
  static Future<void> runFullTest(String firstName, int userId) async {
    print('🧪 === DÉBUT TEST COMPLET NOTIFICATIONS [${Platform.isIOS ? "iOS" : "Android"}] ===');

    try {
      // Test 1: Vérifier permissions
      bool enabled = await areNotificationsEnabled();
      print('🔐 Permissions activées: $enabled');

      if (!enabled && Platform.isIOS) {
        print('🍎 [iOS] Tentative d\'activation des permissions...');
        enabled = await requestPermissions();
        print('🍎 [iOS] Permissions après demande: $enabled');
      }

      if (!enabled) {
        print('❌ Permissions manquantes - Test arrêté');
        return;
      }

      // Test 2: Notification de bienvenue
      await showWelcomeNotification(firstName, userId);
      await Future.delayed(const Duration(seconds: 2));

      // Test 3: Notification simple
      await showTestNotification(firstName);
      await Future.delayed(const Duration(seconds: 2));

      // Test 4: Test spécifique iOS
      if (Platform.isIOS) {
        await testIOSNotifications(firstName);
        await Future.delayed(const Duration(seconds: 2));
      }

      // Test 5: Notification importante
      await showImportantNotification(
        id: 995,
        title: '🚨 Test Important ${Platform.isIOS ? "🍎" : "🤖"}',
        body: 'Notification critique pour $firstName sur ${Platform.isIOS ? "iOS" : "Android"}',
        payload: 'test_important',
      );

      // Test 6: Vérifier notifications en attente
      final pending = await getPendingNotifications();
      print('📋 ${pending.length} notifications en attente après tests');

      print('✅ === TEST COMPLET TERMINÉ [${Platform.isIOS ? "iOS" : "Android"}] ===');
    } catch (e) {
      print('❌ [${Platform.isIOS ? "iOS" : "Android"}] Erreur pendant le test complet: $e');
    }
  }
}