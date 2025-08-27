import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'evaluation_service.dart';
import 'evaluation_widgets.dart';
import 'evaluation_scheduler.dart';
import 'BackgroundNotificationService.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'splash_screen.dart';
import 'dart:async';
import 'notification_service.dart';
import 'dart:io';

// NOUVELLES PERMISSIONS AJOUTÉES
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:camera/camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser les notifications
  await NotificationService.initialize();

  // Initialiser le service de rappels automatiques
  await BackgroundNotificationService.initialize();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OuiBuddy',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const WebViewPage(),
      },
      debugShowCheckedModeBanner: false,
    );
  }
}

// Modèle pour les données utilisateur
class UserProfile {
  final int? id;
  final String firstName;
  final String? lastName;
  final String? email;
  final int? userId;
  final bool loading;
  final bool isAuthenticated;

  UserProfile({
    this.id,
    required this.firstName,
    this.lastName,
    this.email,
    this.userId,
    this.loading = false,
    this.isAuthenticated = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'],
      firstName: json['first_name'] ?? 'Utilisateur',
      lastName: json['last_name'],
      email: json['email'],
      userId: json['user_id'],
      loading: false,
      isAuthenticated: true,
    );
  }

  factory UserProfile.loading() {
    return UserProfile(
      firstName: 'Chargement...',
      loading: true,
    );
  }

  factory UserProfile.defaultProfile() {
    return UserProfile(
      firstName: 'Utilisateur',
      loading: false,
      isAuthenticated: false,
    );
  }

  factory UserProfile.notAuthenticated() {
    return UserProfile(
      firstName: 'Non connecté',
      loading: false,
      isAuthenticated: false,
    );
  }
}

class WebViewPage extends StatefulWidget {
  const WebViewPage({super.key});

  @override
  State<WebViewPage> createState() => _WebViewPageState();
}

class _WebViewPageState extends State<WebViewPage> with WidgetsBindingObserver {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  int retryCount = 0;

  // NOUVELLES VARIABLES POUR LA GESTION DU TOKEN
  String? sessionToken;
  bool tokenRetrieved = false; 
  bool isTokenRetrieval = false;
  int tokenRetrievalAttempts = 0;
  static const int maxTokenAttempts = 10;

  UserProfile userProfile = UserProfile.loading();
  bool notificationsInitialized = false;
  bool isCheckingAuth = false;
  List<Evaluation> upcomingEvaluations = [];
  EvaluationSummary? evaluationSummary;
  bool isLoadingEvaluations = false;
  String? evaluationError;
  bool showEvaluations = false;

  // NOUVELLES VARIABLES POUR LES PERMISSIONS
  Map<String, bool> permissions = {
    'camera': false,
    'microphone': false,
    'storage': false,
    'photos': false,
  };
  bool permissionsInitialized = false;

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    initController();
    WidgetsBinding.instance.addObserver(this);

    // Initialiser les permissions (vérification seulement)
    _initializePermissions();

    // Démarrer la récupération du token une seule fois
    _startTokenRetrieval();
  }

  // FONCTIONS POUR LES PERMISSIONS - CORRIGÉES

  // Initialiser les permissions - MODIFIÉE pour être comme les notifications
  Future<void> _initializePermissions() async {
    try {
      print('🔐 Initialisation des permissions [${Platform.isIOS ? "iOS" : "Android"}]...');
      
      // Vérifier seulement les permissions actuelles, NE PAS les demander
      await _checkCurrentPermissions();
      
      setState(() {
        permissionsInitialized = true;
      });
      
      print('✅ Permissions initialisées [${Platform.isIOS ? "iOS" : "Android"}]');
      
    } catch (e) {
      print('❌ Erreur initialisation permissions: $e');
    }
  }

  // Vérifier les permissions actuelles
  Future<void> _checkCurrentPermissions() async {
    final results = await Future.wait([
      Permission.camera.status,
      Permission.microphone.status,
      Permission.storage.status,
      Permission.photos.status,
    ]);

    setState(() {
      permissions['camera'] = results[0].isGranted;
      permissions['microphone'] = results[1].isGranted;
      permissions['storage'] = results[2].isGranted;
      permissions['photos'] = results[3].isGranted;
    });

    print('📱 Permissions actuelles: $permissions');
  }

  // Demander une permission spécifique (inspiré des notifications)
  Future<bool> _requestSpecificPermission(Permission permission, String permissionName) async {
    print('🔐 [$permissionName] Demande permission ${Platform.isIOS ? "iOS" : "Android"}...');
    
    try {
      final status = await permission.request();
      print('📱 [${Platform.isIOS ? "iOS" : "Android"}] Résultat $permissionName: $status');
      return status.isGranted;
    } catch (e) {
      print('❌ [$permissionName] Erreur demande permission: $e');
      return false;
    }
  }

  // Vérifier si permission accordée
  Future<bool> _isPermissionGranted(Permission permission, String permissionName) async {
    try {
      final status = await permission.status;
      print('📋 [$permissionName] Statut actuel: $status');
      return status.isGranted;
    } catch (e) {
      print('❌ [$permissionName] Erreur vérification: $e');
      return false;
    }
  }

  // Tester la caméra - CORRIGÉ selon le modèle notifications
  Future<void> _testCamera() async {
    print('📸 [${Platform.isIOS ? "iOS" : "Android"}] Test caméra...');
    
    // Vérifier permission d'abord
    bool hasPermission = await _isPermissionGranted(Permission.camera, 'Camera');
    
    if (!hasPermission) {
      print('❌ Permission caméra manquante - demande...');
      
      // Demander permission directement
      hasPermission = await _requestSpecificPermission(Permission.camera, 'Camera');
      
      // Mettre à jour l'état
      setState(() {
        permissions['camera'] = hasPermission;
      });
      
      if (!hasPermission) {
        print('❌ Permission caméra refusée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Permission caméra refusée'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      
      if (image != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📸 Photo prise: ${image.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Erreur caméra: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur caméra: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Tester la galerie - CORRIGÉ selon le modèle notifications
  Future<void> _testGallery() async {
    print('🖼️ [${Platform.isIOS ? "iOS" : "Android"}] Test galerie...');
    
    bool hasPermission = await _isPermissionGranted(Permission.photos, 'Photos');
    
    if (!hasPermission) {
      print('❌ Permission photos manquante - demande...');
      
      hasPermission = await _requestSpecificPermission(Permission.photos, 'Photos');
      
      setState(() {
        permissions['photos'] = hasPermission;
      });
      
      if (!hasPermission) {
        print('❌ Permission photos refusée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Permission galerie refusée'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('🖼️ Image sélectionnée: ${image.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Erreur galerie: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur galerie: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Tester fichiers - CORRIGÉ selon le modèle notifications
  Future<void> _testFilePicker() async {
    print('📄 [${Platform.isIOS ? "iOS" : "Android"}] Test fichiers...');
    
    bool hasPermission = await _isPermissionGranted(Permission.storage, 'Storage');
    
    if (!hasPermission) {
      print('❌ Permission stockage manquante - demande...');
      
      hasPermission = await _requestSpecificPermission(Permission.storage, 'Storage');
      
      setState(() {
        permissions['storage'] = hasPermission;
      });
      
      if (!hasPermission) {
        print('❌ Permission stockage refusée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Permission fichiers refusée'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.name != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('📄 Fichier sélectionné: ${result.files.single.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Erreur sélecteur fichiers: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur fichiers: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // Test microphone (bonus) - selon le modèle notifications
  Future<void> _testMicrophone() async {
    print('🎤 [${Platform.isIOS ? "iOS" : "Android"}] Test microphone...');
    
    bool hasPermission = await _isPermissionGranted(Permission.microphone, 'Microphone');
    
    if (!hasPermission) {
      print('❌ Permission microphone manquante - demande...');
      
      hasPermission = await _requestSpecificPermission(Permission.microphone, 'Microphone');
      
      setState(() {
        permissions['microphone'] = hasPermission;
      });
      
      if (!hasPermission) {
        print('❌ Permission microphone refusée');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Permission microphone refusée'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎤 Permission microphone accordée'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // Afficher un dialogue d'autorisation (pour redirection vers paramètres)
  void _showPermissionDialog(String permissionName, String permissionKey) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permission $permissionName'),
        content: Text(
          'Pour utiliser cette fonctionnalité, OuiBuddy a besoin d\'accéder à votre $permissionName. '
          'Veuillez autoriser l\'accès dans les paramètres.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Plus tard'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Paramètres'),
          ),
        ],
      ),
    );
  }

  // Afficher le statut des permissions
  void _showPermissionStatus() {
    String status = '';
    permissions.forEach((key, value) {
      status += '${key.toUpperCase()}: ${value ? "✅" : "❌"}\n';
    });

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Statut des permissions'),
        content: Text(status),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initializePermissions();
            },
            child: const Text('Actualiser'),
          ),
        ],
      ),
    );
  }

  // FIN DES NOUVELLES FONCTIONS POUR LES PERMISSIONS

  Future<void> _startTokenRetrieval() async {
    // Attendre 5 secondes que la page se charge
    await Future.delayed(const Duration(seconds: 5));
    await _attemptTokenRetrieval();
  }

  // Initialisation des notifications
  Future<void> initializeNotifications() async {
    try {
      final bool enabled = await NotificationService.areNotificationsEnabled();

      setState(() {
        notificationsInitialized = enabled;
      });

      if (enabled) {
        print('✅ Notifications système activées');
      } else {
        print('⚠️ Notifications système non autorisées');
        _showNotificationPermissionDialog();
      }
    } catch (e) {
      print('❌ Erreur initialisation notifications: $e');
      setState(() {
        notificationsInitialized = false;
      });
    }
  }

  // Méthode pour demander l'autorisation des notifications
  void _showNotificationPermissionDialog() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🔔 Notifications'),
          content: const Text(
              'Pour recevoir les notifications de bienvenue et autres alertes importantes, '
                  'veuillez autoriser les notifications dans les paramètres de votre appareil.'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Plus tard'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await NotificationService.openNotificationSettings();
              },
              child: const Text('Ouvrir paramètres'),
            ),
          ],
        ),
      );
    }
  }

  void initController() {
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            setState(() {
              isLoading = true;
              hasError = false;
            });
            print('🌐 Page starting: $url');
          },
          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });
            print('✅ Page finished: $url');

            if (!tokenRetrieved && !isTokenRetrieval &&
                (url.contains('/dashboard') || url.contains('/301/dashboard'))) {
              print('🎯 Arrivée sur dashboard détectée, démarrage récupération token');
              Future.delayed(const Duration(seconds: 2), () {
                _attemptTokenRetrieval();
              });
            }
          },
          onWebResourceError: (error) {
            print('❌ Web resource error: ${error.errorCode} - ${error.description}');

            if (error.errorCode == -1 || error.description.contains('ERR_CACHE_MISS')) {
              if (retryCount < 3) {
                retryCount++;
                print('🔄 Retry attempt $retryCount');
                reloadPage();
              } else {
                setState(() {
                  hasError = true;
                  isLoading = false;
                });
              }
            }
          },
          onNavigationRequest: (request) {
            print('🧭 Navigation vers: ${request.url}');

            if (!request.url.startsWith('https://ouibuddy.com')) {
              if (request.url.contains('stripe') ||
                  request.url.contains('payment') ||
                  request.url.contains('checkout')) {
                print('🚫 Lien de paiement bloqué: ${request.url}');
                return NavigationDecision.prevent;
              }

              launchUrl(Uri.parse(request.url), mode: LaunchMode.externalApplication);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

    loadDirectUrl();
  }

  void loadDirectUrl() {
    controller.loadRequest(Uri.parse('https://ouibuddy.com'));
  }

  void reloadPage() {
    setState(() {
      isLoading = true;
      hasError = false;
      if (!tokenRetrieved) {
        userProfile = UserProfile.loading();
        isCheckingAuth = false;
      }
    });
    controller.reload();
  }

  Future<void> _attemptTokenRetrieval() async {
    if (isTokenRetrieval || tokenRetrieved || tokenRetrievalAttempts >= maxTokenAttempts) {
      print('⚠️ Récupération token déjà en cours ou terminée');
      return;
    }

    setState(() {
      isTokenRetrieval = true;
    });

    tokenRetrievalAttempts++;
    print('🔍 Tentative de récupération token #$tokenRetrievalAttempts/$maxTokenAttempts');

    try {
      final currentUrl = await controller.runJavaScriptReturningResult('window.location.href');
      final url = currentUrl?.toString().replaceAll('"', '') ?? '';

      print('🌐 URL actuelle pour token: $url');

      final sessionInfo = await extractLaravelSession();

      bool hasValidSession = false;

      if (sessionInfo != null) {
        final activeSession = sessionInfo['hasActiveSession'];

        hasValidSession = activeSession == true ||
            (activeSession is String && activeSession.isNotEmpty);

        print('🔍 Session active détectée: $hasValidSession (type: ${activeSession.runtimeType})');
      }

      if (hasValidSession) {
        print('✅ Token/Session récupéré avec succès après $tokenRetrievalAttempts tentatives');

        await fetchUserProfileViaWebView();

        setState(() {
          tokenRetrieved = true;
          isTokenRetrieval = false;
        });

        if (userProfile.id != null) {
          await _setupNotificationsOnce();
        }

      } else {
        if (url.contains('/login') || url.contains('/auth')) {
          print('🔒 Sur page de login, continue à chercher un token... (${tokenRetrievalAttempts}/$maxTokenAttempts)');
        } else {
          print('❌ Pas de token trouvé sur $url (${tokenRetrievalAttempts}/$maxTokenAttempts)');
        }

        setState(() {
          isTokenRetrieval = false;
        });

        if (tokenRetrievalAttempts < maxTokenAttempts) {
          print('⏰ Prochaine tentative dans 10 secondes...');
          Future.delayed(const Duration(seconds: 10), () {
            _attemptTokenRetrieval();
          });
        } else {
          print('🚫 Maximum de tentatives atteint (${maxTokenAttempts}) pour le token');
          setState(() {
            userProfile = UserProfile.notAuthenticated();
          });
        }
      }

    } catch (e) {
      print('❌ Erreur récupération token: $e');
      setState(() {
        isTokenRetrieval = false;
      });

      if (tokenRetrievalAttempts < maxTokenAttempts) {
        print('⏰ Retry après erreur dans 10 secondes...');
        Future.delayed(const Duration(seconds: 10), () {
          _attemptTokenRetrieval();
        });
      }
    }
  }

  Future<void> _setupNotificationsOnce() async {
    if (userProfile.id == null || !notificationsInitialized) {
      print('⚠️ Conditions non réunies pour notifications');
      return;
    }

    try {
      print('📱 Configuration unique des notifications...');

      await NotificationService.showWelcomeNotification(
        userProfile.firstName,
        userProfile.id!,
      );

      await fetchUserEvaluations();

      await scheduleEvaluationNotifications();

      print('✅ Notifications configurées avec succès');

    } catch (e) {
      print('❌ Erreur configuration notifications: $e');
    }
  }

  Future<Map<String, dynamic>?> extractLaravelSession() async {
    try {
      print('🔍 Extraction session Laravel...');

      final result = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          const cookies = document.cookie;
          const sessionInfo = {
            cookies: cookies,
            laravel_session: null,
            xsrf_token: null,
            csrf_token: null,
            hasSession: false
          };
          
          const cookieArray = cookies.split(';');
          for (let cookie of cookieArray) {
            const [name, value] = cookie.trim().split('=');
            if (name === 'laravel_session') {
              sessionInfo.laravel_session = value;
              sessionInfo.hasSession = true;
            }
            if (name === 'XSRF-TOKEN') {
              sessionInfo.xsrf_token = decodeURIComponent(value);
            }
          }
          
          const csrfMeta = document.querySelector('meta[name="csrf-token"]');
          if (csrfMeta) {
            sessionInfo.csrf_token = csrfMeta.getAttribute('content');
          }
          
          const currentUrl = window.location.href;
          const isOnDashboard = currentUrl.includes('/dashboard') || currentUrl.includes('/301/dashboard');
          
          sessionInfo.hasActiveSession = ((sessionInfo.laravel_session && 
                                         (sessionInfo.xsrf_token || sessionInfo.csrf_token)) ||
                                        (isOnDashboard && sessionInfo.csrf_token)) ? true : false;
          
          return JSON.stringify(sessionInfo);
        } catch (error) {
          return JSON.stringify({
            error: error.message,
            hasActiveSession: false
          });
        }
      })()
    ''');

      if (result != null && result.toString() != 'null') {
        String cleanResult = result.toString();

        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }

        cleanResult = cleanResult.replaceAll('\\"', '"');
        cleanResult = cleanResult.replaceAll('\\\\', '\\');

        final sessionData = json.decode(cleanResult);
        print('🍪 Session data: $sessionData');

        if (sessionData['hasActiveSession'] == true) {
          sessionToken = sessionData['laravel_session'] ?? 'dashboard_session';
          return sessionData;
        }
      }

      return null;
    } catch (e) {
      print('❌ Erreur extraction session: $e');
      return null;
    }
  }

  Future<void> fetchUserProfileViaWebView() async {
    try {
      print('🔍 Récupération profil via API...');

      final result = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          var csrfToken = document.querySelector('meta[name="csrf-token"]');
          if (!csrfToken) {
            return JSON.stringify({
              success: false,
              error: 'Token CSRF manquant'
            });
          }
          
          var tokenValue = csrfToken.getAttribute('content');
          var xhr = new XMLHttpRequest();
          
          xhr.open('GET', '/profile/connected/basic', false);
          xhr.setRequestHeader('X-CSRF-TOKEN', tokenValue);
          xhr.setRequestHeader('Accept', 'application/json');
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
          
          try {
            xhr.send();
            
            if (xhr.status === 200) {
              var responseData = JSON.parse(xhr.responseText);
              return JSON.stringify({
                success: true,
                data: responseData,
                status: xhr.status
              });
            } else {
              return JSON.stringify({
                success: false,
                status: xhr.status,
                error: 'Erreur HTTP ' + xhr.status
              });
            }
            
          } catch (networkError) {
            return JSON.stringify({
              success: false,
              error: 'Erreur réseau: ' + networkError.message
            });
          }
          
        } catch (globalError) {
          return JSON.stringify({
            success: false,
            error: 'Erreur globale: ' + globalError.message
          });
        }
      })()
    ''');

      if (result != null && result.toString() != 'null') {
        await handleApiResponse(result.toString());
      } else {
        print('❌ Pas de résultat API');
      }
    } catch (e) {
      print('❌ Erreur récupération profil: $e');
    }
  }

  Future<void> handleApiResponse(String resultString) async {
    try {
      String cleanResult = resultString;

      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.substring(1, cleanResult.length - 1);
      }

      cleanResult = cleanResult.replaceAll('\\"', '"');
      cleanResult = cleanResult.replaceAll('\\\\', '\\');

      final response = json.decode(cleanResult);
      print('📡 Réponse API: $response');

      if (response['success'] == true && response['data'] != null) {
        final apiData = response['data'];

        if (apiData['success'] == true && apiData['data'] != null) {
          final profileData = apiData['data'];

          setState(() {
            userProfile = UserProfile.fromJson(profileData);
          });

          print('✅ PROFIL RÉCUPÉRÉ: ${userProfile.firstName} (ID: ${userProfile.id})');

        } else {
          print('❌ Format API inattendu: $apiData');
        }
      } else {
        print('❌ Échec API: $response');
      }
    } catch (parseError) {
      print('❌ Erreur parsing API: $parseError');
    }
  }

  Future<void> scheduleEvaluationNotifications() async {
    if (!notificationsInitialized || userProfile.id == null) {
      print('⚠️ Conditions non réunies pour programmer les notifications');
      return;
    }

    try {
      print('⏰ Programmation notifications évaluations...');

      await BackgroundNotificationService.scheduleFromEvaluations(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );

      print('✅ Notifications programmées avec succès');

    } catch (e) {
      print('❌ Erreur programmation notifications: $e');
    }
  }

  Future<void> _checkBackgroundReminders() async {
    if (!tokenRetrieved || userProfile.id == null) {
      print('⚠️ Token non récupéré ou pas d\'utilisateur');
      return;
    }

    try {
      await BackgroundNotificationService.checkAndReschedule(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );
    } catch (e) {
      print('❌ Erreur vérification rappels: $e');
    }
  }

  // Méthode de test des notifications
  Future<void> testNotifications() async {
    if (!notificationsInitialized) {
      print('❌ Notifications non autorisées');

      if (Platform.isIOS) {
        final bool granted = await NotificationService.requestPermissions();
        setState(() {
          notificationsInitialized = granted;
        });

        if (!granted) {
          _showNotificationPermissionDialog();
          return;
        }
      } else {
        _showNotificationPermissionDialog();
        return;
      }
    }

    try {
      await NotificationService.showTestNotification(userProfile.firstName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 [${Platform.isIOS ? "iOS" : "Android"}] Notification de test envoyée !'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur test notifications: $e');
    }
  }

  Future<void> fetchUserEvaluations() async {
    if (userProfile.id == null) {
      print('⚠️ Pas d\'utilisateur connecté pour récupérer les évaluations');
      return;
    }

    setState(() {
      isLoadingEvaluations = true;
      evaluationError = null;
    });

    try {
      print('📚 === DEBUG API ÉVALUATIONS ===');
      print('👤 Utilisateur: ${userProfile.firstName} (ID: ${userProfile.id})');
      print('📱 Plateforme: ${Platform.isIOS ? "iOS" : "Android"}');

      if (Platform.isIOS) {
        await fetchUserEvaluationsIOS();
      } else {
        await fetchUserEvaluationsAndroid();
      }

    } catch (e) {
      print('❌ Erreur générale: $e');
      setState(() {
        evaluationError = 'Erreur: ${e.toString()}';
        isLoadingEvaluations = false;
        upcomingEvaluations = [];
        evaluationSummary = null;
        showEvaluations = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  // Version iOS des évaluations (XMLHttpRequest synchrone)
  Future<void> fetchUserEvaluationsIOS() async {
    try {
      print('🍎 [iOS] Récupération évaluations...');

      await controller.runJavaScript('''
        (function() {
          try {
            window.debugApiStatus = 'ios_attempting';
            window.debugApiData = null;
            
            var csrfMeta = document.querySelector('meta[name="csrf-token"]');
            if (!csrfMeta) {
              window.debugApiStatus = 'no_csrf';
              return;
            }
            
            var tokenValue = csrfMeta.getAttribute('content');
            var xhr = new XMLHttpRequest();
            
            xhr.open('GET', '/api/upcoming-evaluations?days_ahead=14&include_today=true&per_page=50', false);
            xhr.setRequestHeader('Accept', 'application/json');
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', tokenValue);
            xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
            
            xhr.send();
            
            if (xhr.status === 200) {
              try {
                var jsonData = JSON.parse(xhr.responseText);
                window.debugApiData = jsonData;
                window.debugApiStatus = 'ios_success';
              } catch (parseError) {
                window.debugApiData = null;
                window.debugApiStatus = 'parse_error';
                window.debugApiError = parseError.message;
              }
            } else {
              window.debugApiData = null;
              window.debugApiStatus = 'http_error';
              window.debugApiError = 'HTTP ' + xhr.status;
            }
          } catch (error) {
            window.debugApiData = null;
            window.debugApiStatus = 'js_error';
            window.debugApiError = error.message;
          }
        })();
      ''');

      await Future.delayed(const Duration(seconds: 3));
      await processEvaluationResults();

    } catch (e) {
      print('❌ [iOS] Erreur évaluations: $e');
      setState(() {
        evaluationError = '[iOS] ${e.toString()}';
        isLoadingEvaluations = false;
      });
    }
  }

  // Version Android (logique existante avec fetch)
  Future<void> fetchUserEvaluationsAndroid() async {
    await controller.runJavaScript('''
      fetch('/api/upcoming-evaluations?days_ahead=14&include_today=true&per_page=50', {
        method: 'GET',
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'X-CSRF-TOKEN': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        },
        credentials: 'same-origin'
      })
      .then(function(response) {
        return response.text();
      })
      .then(function(rawText) {
        try {
          const jsonData = JSON.parse(rawText);
          window.debugApiData = jsonData;
          window.debugApiStatus = 'success';
        } catch (parseError) {
          window.debugApiData = null;
          window.debugApiStatus = 'parse_error';
          window.debugApiError = parseError.message;
        }
      })
      .catch(function(error) {
        window.debugApiData = null;
        window.debugApiStatus = 'fetch_error';
        window.debugApiError = error.message;
      });
    ''');

    await Future.delayed(const Duration(seconds: 3));
    await processEvaluationResults();
  }

  // Méthode commune pour traiter les résultats des évaluations
  Future<void> processEvaluationResults() async {
    final debugInfo = await controller.runJavaScriptReturningResult('''
      JSON.stringify({
        status: window.debugApiStatus || 'unknown',
        hasData: window.debugApiData !== null && window.debugApiData !== undefined,
        error: window.debugApiError || null,
        dataType: window.debugApiData ? typeof window.debugApiData : null,
        dataStatus: window.debugApiData ? window.debugApiData.status : null,
        dataCount: window.debugApiData && window.debugApiData.data ? window.debugApiData.data.length : null
      })
    ''');

    if (debugInfo != null) {
      try {
        String cleanDebugInfo = debugInfo.toString();
        if (cleanDebugInfo.startsWith('"') && cleanDebugInfo.endsWith('"')) {
          cleanDebugInfo = cleanDebugInfo.substring(1, cleanDebugInfo.length - 1);
        }
        cleanDebugInfo = cleanDebugInfo.replaceAll('\\"', '"');

        final debug = json.decode(cleanDebugInfo);
        print('🔍 [${Platform.isIOS ? "iOS" : "Android"}] Debug info: $debug');

        if ((debug['status'] == 'success' || debug['status'] == 'ios_success') && debug['hasData'] == true) {
          final fullData = await controller.runJavaScriptReturningResult('''
            window.debugApiData ? JSON.stringify(window.debugApiData) : null
          ''');

          if (fullData != null) {
            String cleanData = fullData.toString();
            if (cleanData.startsWith('"') && cleanData.endsWith('"')) {
              cleanData = cleanData.substring(1, cleanData.length - 1);
            }
            cleanData = cleanData.replaceAll('\\"', '"');
            cleanData = cleanData.replaceAll('\\\\', '\\');

            final apiData = json.decode(cleanData);

            try {
              final evaluations = EvaluationService.parseEvaluations(apiData);
              final summary = EvaluationService.parseSummary(apiData);

              setState(() {
                upcomingEvaluations = evaluations;
                evaluationSummary = summary;
                isLoadingEvaluations = false;
                showEvaluations = true;
                evaluationError = null;
              });

              if (evaluations.isNotEmpty && userProfile.id != null && notificationsInitialized) {
                await BackgroundNotificationService.scheduleFromEvaluations(
                  userProfile.firstName,
                  userProfile.id!,
                  evaluations,
                );
                print('🔄 Rappels automatiques (8h) mis à jour avec ${evaluations.length} évaluations');
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('✅ [${Platform.isIOS ? "iOS" : "Android"}] ${evaluations.length} évaluations trouvées !'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }

            } catch (parseError) {
              print('❌ Erreur parsing avec EvaluationService: $parseError');
              throw parseError;
            }
          } else {
            throw Exception('Impossible de récupérer les données complètes');
          }
        } else {
          String errorMsg = debug['error']?.toString() ?? 'Erreur de récupération des données';
          throw Exception(errorMsg);
        }
      } catch (e) {
        print('❌ Erreur traitement debug: $e');
        throw e;
      }
    } else {
      throw Exception('Aucune information de debug disponible');
    }
  }

  // Fonction pour notifier les évaluations urgentes
  Future<void> notifyUrgentEvaluations() async {
    if (!notificationsInitialized || upcomingEvaluations.isEmpty) {
      print('⚠️ Notifications non autorisées ou aucune évaluation');
      return;
    }

    try {
      final urgentEvaluations = upcomingEvaluations.where((eval) =>
      eval.isToday || eval.isTomorrow || eval.daysUntil <= 2
      ).toList();

      if (urgentEvaluations.isEmpty) {
        print('📱 Aucune évaluation urgente à notifier');
        return;
      }

      print('🚨 ${urgentEvaluations.length} évaluations urgentes trouvées');

      for (final eval in urgentEvaluations) {
        String title = '';
        bool isImportant = false;

        if (eval.isToday) {
          title = '⚠️ Évaluation AUJOURD\'HUI !';
          isImportant = true;
        } else if (eval.isTomorrow) {
          title = '📅 Évaluation DEMAIN';
          isImportant = true;
        } else {
          title = '📚 Évaluation dans ${eval.daysUntil} jours';
          isImportant = false;
        }

        String body = '';
        if (eval.topicCategory?.name != null) {
          body += '${eval.topicCategory!.name}: ';
        }
        body += eval.description ?? 'Évaluation';
        body += '\n📅 ${eval.evaluationDateFormatted}';

        await NotificationService.showNotification(
          id: 100 + eval.id,
          title: title,
          body: body,
          payload: 'evaluation_${eval.id}',
          isImportant: isImportant,
        );

        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (urgentEvaluations.length > 1) {
        final todayCount = urgentEvaluations.where((e) => e.isToday).length;
        final tomorrowCount = urgentEvaluations.where((e) => e.isTomorrow).length;
        final soonCount = urgentEvaluations.where((e) => !e.isToday && !e.isTomorrow).length;

        String summaryBody = '';
        if (todayCount > 0) {
          summaryBody += '$todayCount aujourd\'hui';
        }
        if (tomorrowCount > 0) {
          if (summaryBody.isNotEmpty) summaryBody += ', ';
          summaryBody += '$tomorrowCount demain';
        }
        if (soonCount > 0) {
          if (summaryBody.isNotEmpty) summaryBody += ', ';
          summaryBody += '$soonCount bientôt';
        }

        await NotificationService.showNotification(
          id: 200,
          title: '📚 Résumé: ${urgentEvaluations.length} évaluations urgentes',
          body: summaryBody,
          payload: 'evaluations_summary',
          isImportant: todayCount > 0,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 [${Platform.isIOS ? "iOS" : "Android"}] ${urgentEvaluations.length} notifications envoyées pour les évaluations urgentes'),
            backgroundColor: urgentEvaluations.any((e) => e.isToday) ? Colors.red : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }

    } catch (e) {
      print('❌ Erreur envoi notifications évaluations: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur notifications: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // Afficher les évaluations dans un bottom sheet
  void _showEvaluationsBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.school, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Mes évaluations ${Platform.isIOS ? "🍎" : "🤖"}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => fetchUserEvaluations(),
                    icon: Icon(
                      Icons.refresh,
                      color: isLoadingEvaluations ? Colors.orange : Colors.blue,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            Expanded(
              child: EvaluationsList(
                evaluations: upcomingEvaluations,
                summary: evaluationSummary,
                isLoading: isLoadingEvaluations,
                errorMessage: evaluationError,
                onRefresh: fetchUserEvaluations,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App reprise');
        if (tokenRetrieved) {
          _checkBackgroundReminders();
        }
        break;
      case AppLifecycleState.paused:
        print('📱 App en pause - rappels automatiques (8h) continuent');
        break;
      case AppLifecycleState.detached:
        print('📱 App fermée - rappels automatiques (8h) actifs');
        break;
      case AppLifecycleState.inactive:
        print('📱 App inactive');
        break;
      case AppLifecycleState.hidden:
        print('📱 App cachée');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // WebView principal
            WebViewWidget(controller: controller),

            // Indicateur de chargement
            if (isLoading)
              const Center(
                child: CircularProgressIndicator(),
              ),

            // Indicateur d'erreur
            if (hasError)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 50),
                    const SizedBox(height: 20),
                    const Text('Impossible de charger la page'),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: () {
                        retryCount = 0;
                        loadDirectUrl();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('Réessayer'),
                    ),
                  ],
                ),
              ),

            // Petit indicateur de statut utilisateur connecté
            if (userProfile.id != null && !userProfile.loading)
              Positioned(
                top: 10,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: tokenRetrieved ? Colors.green : Colors.orange,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        tokenRetrieved ? Icons.check_circle : Icons.person,
                        color: Colors.white,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        userProfile.firstName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Indicateur statut permissions
            if (permissionsInitialized)
              Positioned(
                top: 10,
                right: 80,
                child: GestureDetector(
                  onTap: _showPermissionStatus,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      color: permissions.values.every((p) => p) ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          permissions.values.every((p) => p) ? Icons.security : Icons.warning,
                          color: Colors.white,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${permissions.values.where((p) => p).length}/${permissions.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Indicateur de récupération du token
            if (isTokenRetrieval)
              Positioned(
                top: 10,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Token $tokenRetrievalAttempts/$maxTokenAttempts',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      
      // Menu d'actions flottant
      floatingActionButton: tokenRetrieved ? FloatingActionButton(
        onPressed: () => _showActionsMenu(),
        backgroundColor: Colors.blue,
        child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  // Menu d'actions
  void _showActionsMenu() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Actions disponibles',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Test caméra
            ListTile(
              leading: Icon(
                Icons.camera_alt,
                color: permissions['camera']! ? Colors.green : Colors.red,
              ),
              title: const Text('Tester la caméra'),
              subtitle: Text(permissions['camera']! ? 'Autorisée' : 'Non autorisée'),
              onTap: () {
                Navigator.pop(context);
                _testCamera();
              },
            ),
            
            // Test galerie
            ListTile(
              leading: Icon(
                Icons.photo_library,
                color: permissions['photos']! ? Colors.green : Colors.red,
              ),
              title: const Text('Tester la galerie'),
              subtitle: Text(permissions['photos']! ? 'Autorisée' : 'Non autorisée'),
              onTap: () {
                Navigator.pop(context);
                _testGallery();
              },
            ),
            
            // Test fichiers
            ListTile(
              leading: Icon(
                Icons.folder,
                color: permissions['storage']! ? Colors.green : Colors.red,
              ),
              title: const Text('Sélectionner un fichier'),
              subtitle: Text(permissions['storage']! ? 'Autorisée' : 'Non autorisée'),
              onTap: () {
                Navigator.pop(context);
                _testFilePicker();
              },
            ),
            
            // Test microphone
            ListTile(
              leading: Icon(
                Icons.mic,
                color: permissions['microphone']! ? Colors.green : Colors.red,
              ),
              title: const Text('Tester le microphone'),
              subtitle: Text(permissions['microphone']! ? 'Autorisée' : 'Non autorisée'),
              onTap: () {
                Navigator.pop(context);
                _testMicrophone();
              },
            ),
            
            const Divider(),
            
            // Autres actions existantes
            ListTile(
              leading: const Icon(Icons.school, color: Colors.blue),
              title: const Text('Mes évaluations'),
              onTap: () {
                Navigator.pop(context);
                _showEvaluationsBottomSheet();
              },
            ),
            
            ListTile(
              leading: const Icon(Icons.notifications, color: Colors.orange),
              title: const Text('Test notifications'),
              onTap: () {
                Navigator.pop(context);
                testNotifications();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
