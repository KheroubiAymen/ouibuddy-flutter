import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();

  static Future<void> initialize() async {
    print('🔔 Initialisation des notifications système...');

    // Configuration Android
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // Configuration iOS
    const DarwinInitializationSettings initializationSettingsIOS =
    DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
      requestCriticalPermission: true,
      defaultPresentAlert: true,
      defaultPresentSound: true,
      defaultPresentBadge: true,
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

  // Demander les permissions pour les notifications
  static Future<void> _requestPermissions() async {
    print('🔐 Demande des permissions notifications...');

    try {
      // Permission Android
      if (await Permission.notification.isDenied) {
        final result = await Permission.notification.request();
        print('📱 Permission Android: $result');
      }

      // Permissions iOS spécifiques
      final IOSFlutterLocalNotificationsPlugin? iosImplementation =
      _notifications.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (iosImplementation != null) {
        final bool? granted = await iosImplementation.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
          critical: true,
        );
        print('📱 Permissions iOS accordées: $granted');
      }

      // Vérifier le statut final
      final status = await Permission.notification.status;
      print('📊 Statut final permission notification: $status');
    } catch (e) {
      print('❌ Erreur demande permissions: $e');
    }
  }

  // Créer un canal de notification pour Android
  static Future<void> _createNotificationChannel() async {
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

  // Afficher notification de bienvenue
  static Future<void> showWelcomeNotification(String firstName, int userId) async {
    print('📱 Envoi notification système de bienvenue...');

    try {
      // CORRECTION : Créer les détails de notification dynamiquement
      final NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
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
            'Bienvenue sur OuiBuddy ! Vous êtes maintenant connecté avec succès.',
            summaryText: 'OuiBuddy',
            contentTitle: '👋 Salut $firstName !', // CORRECTION : Maintenant dynamique
          ),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          badgeNumber: 1,
          subtitle: 'Connexion réussie',
          threadIdentifier: 'ouibuddy_welcome',
          interruptionLevel: InterruptionLevel.active,
        ),
      );

      await _notifications.show(
        userId,
        '👋 Salut $firstName !',
        'Connexion réussie sur OuiBuddy',
        notificationDetails,
        payload: 'welcome_$userId',
      );

      print('✅ Notification système de bienvenue envoyée avec succès');
    } catch (e) {
      print('❌ Erreur envoi notification de bienvenue: $e');
    }
  }

  // Afficher notification personnalisée
  static Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
    bool isImportant = false,
  }) async {
    print('📱 Envoi notification système personnalisée...');

    try {
      final NotificationDetails notificationDetails = NotificationDetails(
        android: AndroidNotificationDetails(
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
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'default',
          subtitle: 'OuiBuddy',
          threadIdentifier: 'ouibuddy_general',
          interruptionLevel: isImportant
              ? InterruptionLevel.critical
              : InterruptionLevel.active,
        ),
      );

      await _notifications.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );

      print('✅ Notification système personnalisée envoyée');
    } catch (e) {
      print('❌ Erreur envoi notification personnalisée: $e');
    }
  }

  // Notification de test simple
  static Future<void> showTestNotification(String firstName) async {
    print('🧪 Envoi notification de test...');

    try {
      await showNotification(
        id: 999,
        title: '🧪 Test OuiBuddy',
        body: 'Notification de test pour $firstName - Tout fonctionne !',
        payload: 'test_notification',
        isImportant: false,
      );

      print('✅ Notification de test envoyée');
    } catch (e) {
      print('❌ Erreur notification de test: $e');
    }
  }

  // Notification importante (urgente)
  static Future<void> showImportantNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    print('🚨 Envoi notification importante...');

    try {
      await showNotification(
        id: id,
        title: title,
        body: body,
        payload: payload,
        isImportant: true,
      );

      print('✅ Notification importante envoyée');
    } catch (e) {
      print('❌ Erreur notification importante: $e');
    }
  }

  // Gérer le clic sur notification
  static void _handleNotificationClick(NotificationResponse details) {
    print('🔔 Notification cliquée: ${details.payload}');

    try {
      if (details.payload?.startsWith('welcome_') == true) {
        print('👋 Notification de bienvenue cliquée');
        // Ici vous pouvez naviguer vers une page spécifique
      } else if (details.payload == 'test_notification') {
        print('🧪 Notification de test cliquée');
      } else if (details.payload?.startsWith('scheduled_') == true) {
        print('⏰ Notification programmée cliquée');
      }
    } catch (e) {
      print('❌ Erreur gestion clic notification: $e');
    }
  }

  // Vérifier si les notifications sont autorisées
  static Future<bool> areNotificationsEnabled() async {
    try {
      final status = await Permission.notification.status;
      print('📋 Statut notifications: $status');
      return status == PermissionStatus.granted;
    } catch (e) {
      print('❌ Erreur vérification permissions: $e');
      return false;
    }
  }

  // Ouvrir les paramètres de l'app pour activer les notifications
  static Future<void> openNotificationSettings() async {
    try {
      print('🔧 Ouverture des paramètres de l\'app...');
      await openAppSettings();
    } catch (e) {
      print('❌ Erreur ouverture paramètres: $e');
    }
  }

  // Annuler une notification spécifique
  static Future<void> cancelNotification(int id) async {
    try {
      await _notifications.cancel(id);
      print('✅ Notification $id annulée');
    } catch (e) {
      print('❌ Erreur annulation notification $id: $e');
    }
  }

  // Annuler toutes les notifications
  static Future<void> cancelAllNotifications() async {
    try {
      await _notifications.cancelAll();
      print('✅ Toutes les notifications annulées');
    } catch (e) {
      print('❌ Erreur annulation toutes notifications: $e');
    }
  }

  // Obtenir toutes les notifications en attente
  static Future<List<PendingNotificationRequest>> getPendingNotifications() async {
    try {
      final pending = await _notifications.pendingNotificationRequests();
      print('📋 ${pending.length} notifications en attente');
      return pending;
    } catch (e) {
      print('❌ Erreur récupération notifications en attente: $e');
      return [];
    }
  }

  // Méthode utilitaire pour tester toutes les fonctionnalités
  static Future<void> runFullTest(String firstName, int userId) async {
    print('🧪 === DÉBUT TEST COMPLET NOTIFICATIONS ===');

    try {
      // Test 1: Vérifier permissions
      final enabled = await areNotificationsEnabled();
      print('🔐 Permissions activées: $enabled');

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

      // Test 4: Notification importante
      await showImportantNotification(
        id: 995,
        title: '🚨 Test Important',
        body: 'Notification critique pour $firstName',
        payload: 'test_important',
      );

      // Test 5: Vérifier notifications en attente
      final pending = await getPendingNotifications();
      print('📋 ${pending.length} notifications en attente après tests');

      print('✅ === TEST COMPLET TERMINÉ ===');
    } catch (e) {
      print('❌ Erreur pendant le test complet: $e');
    }
  }
}