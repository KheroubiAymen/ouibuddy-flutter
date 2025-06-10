// NOUVEAU FICHIER : background_notification_service.dart

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'dart:convert';
import 'notification_service.dart';

class BackgroundNotificationService {
  static const String _backgroundChannelId = 'background_reminders';
  static const int _backgroundNotificationId = 5000;
  static const int _periodicReminderBaseId = 6000;

  // Initialiser le service de notifications en arrière-plan
  static Future<void> initialize() async {
    print('🔄 Initialisation service notifications arrière-plan...');

    try {
      // Initialiser les fuseaux horaires
      tz.initializeTimeZones();

      // Créer le canal de notification pour l'arrière-plan
      await _createBackgroundNotificationChannel();

      print('✅ Service arrière-plan initialisé');
    } catch (e) {
      print('❌ Erreur initialisation arrière-plan: $e');
    }
  }

  // Créer le canal de notification pour les rappels en arrière-plan
  static Future<void> _createBackgroundNotificationChannel() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
    notifications.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    if (androidImplementation != null) {
      await androidImplementation.createNotificationChannel(
        const AndroidNotificationChannel(
          _backgroundChannelId,
          'Rappels automatiques',
          description: 'Rappels automatiques des évaluations toutes les 5 minutes',
          importance: Importance.high,
          enableVibration: true,
          playSound: true,
          showBadge: true,
        ),
      );

      print('📺 Canal de notifications arrière-plan créé');
    }
  }

  // Programmer les rappels toutes les 5 minutes
  static Future<void> schedulePeriodicReminders({
    required String userName,
    required int userId,
    required List<Map<String, dynamic>> urgentEvaluations,
  }) async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      print('⏰ Programmation rappels périodiques toutes les 5 minutes...');

      // Annuler les anciens rappels périodiques
      await cancelPeriodicReminders();

      if (urgentEvaluations.isEmpty) {
        print('ℹ️ Aucune évaluation urgente, pas de rappels périodiques');
        return;
      }

      // Programmer les rappels pour les 2 prochaines heures (24 rappels de 5 min)
      final now = tz.TZDateTime.now(tz.local);

      for (int i = 1; i <= 24; i++) { // 24 rappels = 2 heures
        final reminderTime = now.add(Duration(minutes: i * 5));

        // Créer le message de rappel
        String reminderMessage = _createReminderMessage(urgentEvaluations, i);

        await notifications.zonedSchedule(
          _periodicReminderBaseId + i,
          '🔔 Rappel évaluations',
          reminderMessage,
          reminderTime,
          NotificationDetails(
            android: AndroidNotificationDetails(
              _backgroundChannelId,
              'Rappels automatiques',
              channelDescription: 'Rappels automatiques des évaluations',
              importance: _getImportanceForReminder(urgentEvaluations),
              priority: _getPriorityForReminder(urgentEvaluations),
              icon: '@mipmap/ic_launcher',
              color: Colors.orange,
              enableVibration: true,
              playSound: true,
              autoCancel: true,
              ongoing: false,
              styleInformation: BigTextStyleInformation(
                reminderMessage,
                summaryText: 'OuiBuddy - Rappel automatique',
                contentTitle: '🔔 Rappel évaluations',
              ),
            ),
            iOS: DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
              sound: 'default',
              subtitle: 'Rappel automatique',
              threadIdentifier: 'periodic_reminder',
              interruptionLevel: _hasEvaluationsToday(urgentEvaluations)
                  ? InterruptionLevel.critical
                  : InterruptionLevel.active,
            ),
          ),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
          payload: json.encode({
            'type': 'periodic_reminder',
            'user_id': userId,
            'user_name': userName,
            'reminder_number': i,
            'evaluations_count': urgentEvaluations.length,
            'scheduled_at': reminderTime.toIso8601String(),
          }),
        );
      }

      print('✅ ${24} rappels périodiques programmés pour les 2 prochaines heures');

      // Programmer la reprogrammation automatique dans 2 heures
      await _scheduleReprogramming(userName, userId, urgentEvaluations);

    } catch (e) {
      print('❌ Erreur programmation rappels périodiques: $e');
    }
  }

  // Créer le message de rappel personnalisé
  static String _createReminderMessage(List<Map<String, dynamic>> evaluations, int reminderNumber) {
    final todayEvaluations = evaluations.where((e) => e['isToday'] == true).toList();
    final tomorrowEvaluations = evaluations.where((e) => e['isTomorrow'] == true).toList();
    final soonEvaluations = evaluations.where((e) =>
    e['isToday'] != true && e['isTomorrow'] != true && e['daysUntil'] <= 3
    ).toList();

    String message = '';

    if (todayEvaluations.isNotEmpty) {
      message += '🚨 ${todayEvaluations.length} évaluation(s) AUJOURD\'HUI !\n';
      for (final eval in todayEvaluations.take(2)) { // Max 2 pour la lisibilité
        message += '• ${eval['topic'] ?? 'Matière'}: ${eval['description'] ?? 'Évaluation'}\n';
      }
      if (todayEvaluations.length > 2) {
        message += '• ... et ${todayEvaluations.length - 2} autre(s)\n';
      }
    }

    if (tomorrowEvaluations.isNotEmpty) {
      message += '⚠️ ${tomorrowEvaluations.length} évaluation(s) DEMAIN\n';
      for (final eval in tomorrowEvaluations.take(1)) {
        message += '• ${eval['topic'] ?? 'Matière'}: ${eval['description'] ?? 'Évaluation'}\n';
      }
    }

    if (soonEvaluations.isNotEmpty && message.length < 100) { // Éviter les messages trop longs
      message += '📚 ${soonEvaluations.length} autre(s) cette semaine';
    }

    if (message.isEmpty) {
      message = '📚 Vérifiez vos évaluations à venir';
    }

    // Ajouter un indicateur de progression
    final timeElapsed = reminderNumber * 5;
    message += '\n⏰ Rappel automatique (${timeElapsed}min)';

    return message.trim();
  }

  // Déterminer l'importance de la notification
  static Importance _getImportanceForReminder(List<Map<String, dynamic>> evaluations) {
    if (evaluations.any((e) => e['isToday'] == true)) {
      return Importance.max; // Critique pour aujourd'hui
    } else if (evaluations.any((e) => e['isTomorrow'] == true)) {
      return Importance.high; // Important pour demain
    }
    return Importance.defaultImportance; // Normal pour le reste
  }

  // Déterminer la priorité de la notification
  static Priority _getPriorityForReminder(List<Map<String, dynamic>> evaluations) {
    if (evaluations.any((e) => e['isToday'] == true)) {
      return Priority.max;
    } else if (evaluations.any((e) => e['isTomorrow'] == true)) {
      return Priority.high;
    }
    return Priority.defaultPriority;
  }

  // Vérifier s'il y a des évaluations aujourd'hui
  static bool _hasEvaluationsToday(List<Map<String, dynamic>> evaluations) {
    return evaluations.any((e) => e['isToday'] == true);
  }

  // Programmer la reprogrammation automatique
  static Future<void> _scheduleReprogramming(
      String userName,
      int userId,
      List<Map<String, dynamic>> urgentEvaluations,
      ) async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      final reprogramTime = tz.TZDateTime.now(tz.local).add(const Duration(hours: 2));

      await notifications.zonedSchedule(
        _backgroundNotificationId,
        '🔄 Reprogrammation automatique',
        'Renouvellement des rappels d\'évaluations',
        reprogramTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _backgroundChannelId,
            'Rappels automatiques',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: false,
            autoCancel: true,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: json.encode({
          'type': 'auto_reprogram',
          'user_id': userId,
          'user_name': userName,
          'evaluations': urgentEvaluations,
        }),
      );

      print('⏰ Reprogrammation automatique prévue dans 2 heures');
    } catch (e) {
      print('❌ Erreur programmation reprogrammation: $e');
    }
  }

  // Annuler tous les rappels périodiques
  static Future<void> cancelPeriodicReminders() async {
    final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

    try {
      // Annuler la reprogrammation
      await notifications.cancel(_backgroundNotificationId);

      // Annuler tous les rappels périodiques
      for (int i = 1; i <= 50; i++) { // Un peu plus large pour être sûr
        await notifications.cancel(_periodicReminderBaseId + i);
      }

      print('✅ Tous les rappels périodiques annulés');
    } catch (e) {
      print('❌ Erreur annulation rappels périodiques: $e');
    }
  }

  // Programmer les rappels à partir des évaluations
  static Future<void> scheduleFromEvaluations(
      String userName,
      int userId,
      List<dynamic> evaluations, // Liste des objets Evaluation
      ) async {
    try {
      // Convertir les évaluations en format Map pour le stockage
      final urgentEvaluations = evaluations
          .where((eval) => eval.isToday || eval.isTomorrow || eval.daysUntil <= 3)
          .map((eval) => {
        'id': eval.id,
        'description': eval.description ?? 'Évaluation',
        'topic': eval.topicCategory?.name ?? 'Matière',
        'date': eval.evaluationDateFormatted,
        'isToday': eval.isToday,
        'isTomorrow': eval.isTomorrow,
        'daysUntil': eval.daysUntil,
        'urgencyText': eval.urgencyText,
      })
          .toList();

      print('📱 Programmation rappels automatiques pour ${urgentEvaluations.length} évaluations urgentes');

      await schedulePeriodicReminders(
        userName: userName,
        userId: userId,
        urgentEvaluations: urgentEvaluations,
      );

    } catch (e) {
      print('❌ Erreur programmation depuis évaluations: $e');
    }
  }

  // Vérifier et reprogrammer si nécessaire (appelé au démarrage de l'app)
  static Future<void> checkAndReschedule(
      String userName,
      int userId,
      List<dynamic> currentEvaluations,
      ) async {
    try {
      print('🔍 Vérification des rappels programmés...');

      final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

      final pending = await notifications.pendingNotificationRequests();
      final periodicReminders = pending.where((notif) =>
      notif.id >= _periodicReminderBaseId && notif.id < _periodicReminderBaseId + 100
      ).toList();

      print('📋 ${periodicReminders.length} rappels périodiques trouvés');

      // Si moins de 5 rappels restants, reprogrammer
      if (periodicReminders.length < 5) {
        print('🔄 Moins de 5 rappels restants, reprogrammation...');
        await scheduleFromEvaluations(userName, userId, currentEvaluations);
      } else {
        print('✅ Rappels suffisants, aucune action nécessaire');
      }

    } catch (e) {
      print('❌ Erreur vérification rappels: $e');
    }
  }

  // Obtenir le statut des rappels programmés
  static Future<Map<String, dynamic>> getReminderStatus() async {
    try {
      final FlutterLocalNotificationsPlugin notifications =
      FlutterLocalNotificationsPlugin();

      final pending = await notifications.pendingNotificationRequests();
      final periodicReminders = pending.where((notif) =>
      notif.id >= _periodicReminderBaseId && notif.id < _periodicReminderBaseId + 100
      ).toList();

      final hasReprogramming = pending.any((notif) => notif.id == _backgroundNotificationId);

      return {
        'total_pending': pending.length,
        'periodic_reminders': periodicReminders.length,
        'has_reprogramming': hasReprogramming,
        'next_reminder': periodicReminders.isNotEmpty
            ? periodicReminders.first.title
            : null,
      };
    } catch (e) {
      print('❌ Erreur récupération statut: $e');
      return {
        'total_pending': 0,
        'periodic_reminders': 0,
        'has_reprogramming': false,
        'error': e.toString(),
      };
    }
  }
}