import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:convert';
import 'evaluation_service.dart';
import 'notification_service.dart';

class EvaluationScheduler {
  static const String _dailyCheckChannelId = 'evaluation_daily_check';
  static const String _reminderChannelId = 'evaluation_reminders';

  // IDs de notifications pour éviter les conflits
  static const int dailyCheckNotificationId = 1000;
  static const int reminder24hBaseId = 2000; // 2000-2999 pour rappels 24h
  static const int reminder48hBaseId = 3000; // 3000-3999 pour rappels 48h
  static const int reminder72hBaseId = 4000; // 4000-4999 pour rappels 72h

  // Initialiser le système de rappels
  static Future<void> initialize() async {
    print('📅 Initialisation du système de rappels d\'évaluations...');

    try {
      // Initialiser les fuseaux horaires
      tz.initializeTimeZones();

      // Créer les canaux de notification spécifiques
      await _createNotificationChannels();

      // Programmer le check quotidien à 18h
      await scheduleDailyEvaluationCheck();

      print('✅ Système de rappels initialisé avec succès');
    } catch (e) {
      print('❌ Erreur initialisation rappels: $e');
    }
  }

  // Créer les canaux de notification pour Android
  static Future<void> _createNotificationChannels() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      // Canal pour le check quotidien
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _dailyCheckChannelId,
          'Vérification quotidienne',
          description: 'Vérification quotidienne des évaluations à venir',
          importance: Importance.low,
          enableVibration: false,
          playSound: false,
        ),
      );

      // Canal pour les rappels d'évaluations
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _reminderChannelId,
          'Rappels évaluations',
          description: 'Rappels des évaluations dans 24h, 48h et 72h',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
        ),
      );

      print('📺 Canaux de notification créés');
    }
  }

  // Programmer le check quotidien à 18h
  static Future<void> scheduleDailyEvaluationCheck() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      // Annuler l'ancien check quotidien s'il existe
      await notifications.cancel(dailyCheckNotificationId);

      // Calculer la prochaine occurrence de 18h
      final now = tz.TZDateTime.now(tz.local);
      tz.TZDateTime scheduledDate = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day,
        18, // 18h
        0,  // 0 minutes
      );

      // Si 18h est déjà passé aujourd'hui, programmer pour demain
      if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      print('⏰ Programmation check quotidien pour: $scheduledDate');

      await notifications.zonedSchedule(
        dailyCheckNotificationId,
        '🔍 Vérification quotidienne',
        'Recherche de nouvelles évaluations...',
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _dailyCheckChannelId,
            'Vérification quotidienne',
            channelDescription: 'Vérification quotidienne des évaluations',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: false,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: false, // Pas d'alerte pour la vérification
            presentBadge: false,
            presentSound: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time, // Répéter chaque jour
        payload: json.encode({
          'type': 'daily_check',
          'scheduled_at': scheduledDate.toIso8601String(),
        }),
      );

      print('✅ Check quotidien programmé pour tous les jours à 18h');
    } catch (e) {
      print('❌ Erreur programmation check quotidien: $e');
    }
  }

  // Effectuer le check quotidien des évaluations
  static Future<void> performDailyEvaluationCheck(
      dynamic webViewController,
      int? userId,
      ) async {
    print('🔍 === DÉBUT CHECK QUOTIDIEN ÉVALUATIONS ===');

    try {
      if (userId == null) {
        print('⚠️ Pas d\'utilisateur connecté pour le check');
        return;
      }

      // Récupérer les évaluations via WebView
      final evaluationsData = await EvaluationService.fetchEvaluationsViaWebView(
        webViewController,
        userId: userId,
        daysAhead: 7, // Vérifier sur 7 jours
      );

      if (evaluationsData == null) {
        print('❌ Impossible de récupérer les évaluations');
        return;
      }

      // Parser les évaluations
      final evaluations = EvaluationService.parseEvaluations(evaluationsData);
      print('📚 ${evaluations.length} évaluations trouvées');

      if (evaluations.isEmpty) {
        print('ℹ️ Aucune évaluation à programmer');
        return;
      }

      // Programmer les rappels pour chaque évaluation
      int programmersCount = 0;
      for (final evaluation in evaluations) {
        final scheduled = await _scheduleRemindersForEvaluation(evaluation);
        if (scheduled) programmersCount++;
      }

      print('✅ $programmersCount évaluations programmées avec rappels');

      // Envoyer une notification de résumé (optionnel)
      if (programmersCount > 0) {
        await _sendDailySummaryNotification(evaluations, programmersCount);
      }

    } catch (e) {
      print('❌ Erreur check quotidien: $e');
    }
  }

  // Programmer les rappels pour une évaluation (24h, 48h, 72h avant)
  static Future<bool> _scheduleRemindersForEvaluation(Evaluation evaluation) async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      final evaluationDate = tz.TZDateTime.from(evaluation.evaluationDate, tz.local);
      final now = tz.TZDateTime.now(tz.local);

      print('📅 Programmation rappels pour: ${evaluation.description} le ${evaluation.evaluationDateFormatted}');

      int scheduledCount = 0;

      // Rappel 72h avant (3 jours)
      final reminder72h = evaluationDate.subtract(const Duration(hours: 72));
      if (reminder72h.isAfter(now)) {
        await _scheduleReminderNotification(
          notifications,
          reminder72hBaseId + evaluation.id,
          '📚 Évaluation dans 3 jours',
          '${evaluation.topicCategory?.name ?? 'Matière'}: ${evaluation.description ?? 'Évaluation'}\nDate: ${evaluation.evaluationDateFormatted}',
          reminder72h,
          evaluation,
          '72h',
        );
        scheduledCount++;
        print('  ✅ Rappel 72h programmé pour: $reminder72h');
      }

      // Rappel 48h avant (2 jours)
      final reminder48h = evaluationDate.subtract(const Duration(hours: 48));
      if (reminder48h.isAfter(now)) {
        await _scheduleReminderNotification(
          notifications,
          reminder48hBaseId + evaluation.id,
          '📚 Évaluation dans 2 jours',
          '${evaluation.topicCategory?.name ?? 'Matière'}: ${evaluation.description ?? 'Évaluation'}\nDate: ${evaluation.evaluationDateFormatted}',
          reminder48h,
          evaluation,
          '48h',
        );
        scheduledCount++;
        print('  ✅ Rappel 48h programmé pour: $reminder48h');
      }

      // Rappel 24h avant (1 jour)
      final reminder24h = evaluationDate.subtract(const Duration(hours: 24));
      if (reminder24h.isAfter(now)) {
        await _scheduleReminderNotification(
          notifications,
          reminder24hBaseId + evaluation.id,
          '⚠️ Évaluation demain !',
          '${evaluation.topicCategory?.name ?? 'Matière'}: ${evaluation.description ?? 'Évaluation'}\nDate: ${evaluation.evaluationDateFormatted}',
          reminder24h,
          evaluation,
          '24h',
        );
        scheduledCount++;
        print('  ✅ Rappel 24h programmé pour: $reminder24h');
      }

      print('  📊 $scheduledCount rappels programmés pour cette évaluation');
      return scheduledCount > 0;

    } catch (e) {
      print('❌ Erreur programmation rappels pour évaluation ${evaluation.id}: $e');
      return false;
    }
  }

  // Programmer une notification de rappel spécifique
  static Future<void> _scheduleReminderNotification(
      FlutterLocalNotificationsPlugin notifications,
      int notificationId,
      String title,
      String body,
      tz.TZDateTime scheduledDate,
      Evaluation evaluation,
      String reminderType,
      ) async {
    try {
      await notifications.zonedSchedule(
        notificationId,
        title,
        body,
        scheduledDate,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _reminderChannelId,
            'Rappels évaluations',
            channelDescription: 'Rappels des évaluations à venir',
            importance: reminderType == '24h' ? Importance.max : Importance.high,
            priority: reminderType == '24h' ? Priority.max : Priority.high,
            icon: '@mipmap/ic_launcher',
            color: Colors.blue ,
            enableVibration: true,
            playSound: true,
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
            threadIdentifier: 'evaluation_reminder',
            interruptionLevel: reminderType == '24h'
                ? InterruptionLevel.critical
                : InterruptionLevel.active,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: json.encode({
          'type': 'evaluation_reminder',
          'evaluation_id': evaluation.id,
          'reminder_type': reminderType,
          'evaluation_date': evaluation.evaluationDate.toIso8601String(),
          'description': evaluation.description,
          'topic': evaluation.topicCategory?.name,
        }),
      );
    } catch (e) {
      print('❌ Erreur programmation notification $notificationId: $e');
    }
  }

  // Envoyer un résumé quotidien (optionnel)
  static Future<void> _sendDailySummaryNotification(
      List<Evaluation> evaluations,
      int scheduledCount,
      ) async {
    try {
      final urgentEvaluations = evaluations.where((e) =>
      e.daysUntil <= 3
      ).toList();

      if (urgentEvaluations.isNotEmpty) {
        String summaryText = '';
        if (urgentEvaluations.any((e) => e.isToday)) {
          final todayCount = urgentEvaluations.where((e) => e.isToday).length;
          summaryText += '$todayCount aujourd\'hui ';
        }
        if (urgentEvaluations.any((e) => e.isTomorrow)) {
          final tomorrowCount = urgentEvaluations.where((e) => e.isTomorrow).length;
          summaryText += '$tomorrowCount demain ';
        }

        await NotificationService.showNotification(
          id: 500, // ID fixe pour le résumé quotidien
          title: '📋 Résumé quotidien',
          body: '${urgentEvaluations.length} évaluations cette semaine. $summaryText',
          payload: 'daily_summary',
          isImportant: urgentEvaluations.any((e) => e.isToday),
        );
      }
    } catch (e) {
      print('❌ Erreur résumé quotidien: $e');
    }
  }

  // Annuler tous les rappels d'une évaluation spécifique
  static Future<void> cancelRemindersForEvaluation(int evaluationId) async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      await notifications.cancel(reminder24hBaseId + evaluationId);
      await notifications.cancel(reminder48hBaseId + evaluationId);
      await notifications.cancel(reminder72hBaseId + evaluationId);

      print('✅ Rappels annulés pour évaluation $evaluationId');
    } catch (e) {
      print('❌ Erreur annulation rappels évaluation $evaluationId: $e');
    }
  }

  // Annuler tous les rappels programmés
  static Future<void> cancelAllReminders() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      // Annuler le check quotidien
      await notifications.cancel(dailyCheckNotificationId);

      // Annuler tous les rappels (on peut optimiser en gardant une liste des IDs)
      for (int i = 0; i < 1000; i++) {
        await notifications.cancel(reminder24hBaseId + i);
        await notifications.cancel(reminder48hBaseId + i);
        await notifications.cancel(reminder72hBaseId + i);
      }

      print('✅ Tous les rappels annulés');
    } catch (e) {
      print('❌ Erreur annulation tous rappels: $e');
    }
  }

  // Obtenir les rappels programmés (diagnostic)
  static Future<void> listScheduledReminders() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      final pending = await notifications.pendingNotificationRequests();
      print('📋 === RAPPELS PROGRAMMÉS ===');
      print('Total: ${pending.length} notifications en attente');

      for (final notif in pending) {
        if (notif.payload != null) {
          try {
            final payloadData = json.decode(notif.payload!);
            print('📅 ID: ${notif.id} - Type: ${payloadData['type']} - Titre: ${notif.title}');
          } catch (e) {
            print('📅 ID: ${notif.id} - Titre: ${notif.title}');
          }
        }
      }
      print('=========================');
    } catch (e) {
      print('❌ Erreur liste rappels: $e');
    }
  }

  // Forcer un check immédiat (pour debug)
  static Future<void> forceEvaluationCheck(
      dynamic webViewController,
      int? userId,
      ) async {
    print('🔧 Force check immédiat des évaluations...');
    await performDailyEvaluationCheck(webViewController, userId);
  }

  // Tester le système avec des notifications de démonstration
  static Future<void> testReminderSystem() async {
    print('🧪 Test du système de rappels...');

    try {
      final now = tz.TZDateTime.now(tz.local);

      // Test notification 1 minute
      await NotificationService.showNotification(
        id: 9001,
        title: '🧪 Test rappel 1 min',
        body: 'Test de notification programmée',
        isImportant: false,
      );

      // Programmer une notification de test dans 2 minutes
      final testDate = now.add(const Duration(minutes: 2));

      final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

      await notifications.zonedSchedule(
        9002,
        '🧪 Test rappel programmé',
        'Cette notification était programmée pour dans 2 minutes',
        testDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Tests',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
      );

      print('✅ Tests programmés : immédiat + 2 minutes');
    } catch (e) {
      print('❌ Erreur test système: $e');
    }
  }
}