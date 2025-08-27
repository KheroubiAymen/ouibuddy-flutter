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

// Permissions
import 'package:permission_handler/permission_handler.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.initialize();
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
    _initializePermissions();
    _startTokenRetrieval();
  }

  Future<void> _initializePermissions() async {
    try {
      print('Initialisation des permissions...');
      await _checkCurrentPermissions();
      setState(() {
        permissionsInitialized = true;
      });
      print('Permissions initialisées');
    } catch (e) {
      print('Erreur initialisation permissions: $e');
    }
  }

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

    print('Permissions actuelles: $permissions');
  }

  Future<void> _testCamera() async {
    print('Test caméra...');
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.camera);
      
      if (image != null) {
        setState(() {
          permissions['camera'] = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Photo prise: ${image.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          permissions['camera'] = false;
        });
      }
    } catch (e) {
      print('Erreur caméra: $e');
      setState(() {
        permissions['camera'] = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission caméra refusée ou erreur'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testGallery() async {
    print('Test galerie...');
    
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null) {
        setState(() {
          permissions['photos'] = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Image sélectionnée: ${image.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          permissions['photos'] = false;
        });
      }
    } catch (e) {
      print('Erreur galerie: $e');
      setState(() {
        permissions['photos'] = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission galerie refusée ou erreur'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testFilePicker() async {
    print('Test fichiers...');
    
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'png'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.name != null) {
        setState(() {
          permissions['storage'] = true;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fichier sélectionné: ${result.files.single.name}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        setState(() {
          permissions['storage'] = false;
        });
      }
    } catch (e) {
      print('Erreur fichiers: $e');
      setState(() {
        permissions['storage'] = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Permission fichiers refusée ou erreur'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testMicrophone() async {
    print('Test microphone...');
    
    try {
      final status = await Permission.microphone.request();
      
      setState(() {
        permissions['microphone'] = status.isGranted;
      });
      
      if (status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Permission microphone accordée'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Permission microphone refusée'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('Erreur microphone: $e');
      setState(() {
        permissions['microphone'] = false;
      });
    }
  }

  Future<void> _startTokenRetrieval() async {
    await Future.delayed(const Duration(seconds: 5));
    await _attemptTokenRetrieval();
  }

  Future<void> initializeNotifications() async {
    try {
      final bool enabled = await NotificationService.areNotificationsEnabled();

      setState(() {
        notificationsInitialized = enabled;
      });

      if (enabled) {
        print('Notifications système activées');
      } else {
        print('Notifications système non autorisées');
        _showNotificationPermissionDialog();
      }
    } catch (e) {
      print('Erreur initialisation notifications: $e');
      setState(() {
        notificationsInitialized = false;
      });
    }
  }

  void _showNotificationPermissionDialog() {
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Notifications'),
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
            print('Page starting: $url');
          },
          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });
            print('Page finished: $url');

            if (!tokenRetrieved && !isTokenRetrieval &&
                (url.contains('/dashboard') || url.contains('/301/dashboard'))) {
              print('Arrivée sur dashboard détectée');
              Future.delayed(const Duration(seconds: 2), () {
                _attemptTokenRetrieval();
              });
            }
          },
          onWebResourceError: (error) {
            print('Web resource error: ${error.errorCode} - ${error.description}');

            if (error.errorCode == -1 || error.description.contains('ERR_CACHE_MISS')) {
              if (retryCount < 3) {
                retryCount++;
                print('Retry attempt $retryCount');
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
            print('Navigation vers: ${request.url}');

            if (!request.url.startsWith('https://ouibuddy.com')) {
              if (request.url.contains('stripe') ||
                  request.url.contains('payment') ||
                  request.url.contains('checkout')) {
                print('Lien de paiement bloqué: ${request.url}');
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
      print('Récupération token déjà en cours ou terminée');
      return;
    }

    setState(() {
      isTokenRetrieval = true;
    });

    tokenRetrievalAttempts++;
    print('Tentative de récupération token #$tokenRetrievalAttempts/$maxTokenAttempts');

    try {
      final currentUrl = await controller.runJavaScriptReturningResult('window.location.href');
      final url = currentUrl?.toString().replaceAll('"', '') ?? '';

      print('URL actuelle pour token: $url');

      final sessionInfo = await extractLaravelSession();

      bool hasValidSession = false;

      if (sessionInfo != null) {
        final activeSession = sessionInfo['hasActiveSession'];
        hasValidSession = activeSession == true ||
            (activeSession is String && activeSession.isNotEmpty);
        print('Session active détectée: $hasValidSession');
      }

      if (hasValidSession) {
        print('Token/Session récupéré avec succès');
        await fetchUserProfileViaWebView();

        setState(() {
          tokenRetrieved = true;
          isTokenRetrieval = false;
        });

        if (userProfile.id != null) {
          await _setupNotificationsOnce();
        }
      } else {
        setState(() {
          isTokenRetrieval = false;
        });

        if (tokenRetrievalAttempts < maxTokenAttempts) {
          print('Prochaine tentative dans 10 secondes...');
          Future.delayed(const Duration(seconds: 10), () {
            _attemptTokenRetrieval();
          });
        } else {
          print('Maximum de tentatives atteint');
          setState(() {
            userProfile = UserProfile.notAuthenticated();
          });
        }
      }
    } catch (e) {
      print('Erreur récupération token: $e');
      setState(() {
        isTokenRetrieval = false;
      });

      if (tokenRetrievalAttempts < maxTokenAttempts) {
        Future.delayed(const Duration(seconds: 10), () {
          _attemptTokenRetrieval();
        });
      }
    }
  }

  Future<void> _setupNotificationsOnce() async {
    if (userProfile.id == null || !notificationsInitialized) {
      print('Conditions non réunies pour notifications');
      return;
    }

    try {
      print('Configuration unique des notifications...');
      await NotificationService.showWelcomeNotification(
        userProfile.firstName,
        userProfile.id!,
      );
      await fetchUserEvaluations();
      await scheduleEvaluationNotifications();
      print('Notifications configurées avec succès');
    } catch (e) {
      print('Erreur configuration notifications: $e');
    }
  }

  Future<Map<String, dynamic>?> extractLaravelSession() async {
    try {
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
        if (sessionData['hasActiveSession'] == true) {
          sessionToken = sessionData['laravel_session'] ?? 'dashboard_session';
          return sessionData;
        }
      }
      return null;
    } catch (e) {
      print('Erreur extraction session: $e');
      return null;
    }
  }

  Future<void> fetchUserProfileViaWebView() async {
    try {
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
      }
    } catch (e) {
      print('Erreur récupération profil: $e');
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

      if (response['success'] == true && response['data'] != null) {
        final apiData = response['data'];
        if (apiData['success'] == true && apiData['data'] != null) {
          final profileData = apiData['data'];
          setState(() {
            userProfile = UserProfile.fromJson(profileData);
          });
          print('PROFIL RÉCUPÉRÉ: ${userProfile.firstName} (ID: ${userProfile.id})');
        }
      }
    } catch (parseError) {
      print('Erreur parsing API: $parseError');
    }
  }

  Future<void> scheduleEvaluationNotifications() async {
    if (!notificationsInitialized || userProfile.id == null) {
      return;
    }

    try {
      await BackgroundNotificationService.scheduleFromEvaluations(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );
    } catch (e) {
      print('Erreur programmation notifications: $e');
    }
  }

  Future<void> _checkBackgroundReminders() async {
    if (!tokenRetrieved || userProfile.id == null) {
      return;
    }

    try {
      await BackgroundNotificationService.checkAndReschedule(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );
    } catch (e) {
      print('Erreur vérification rappels: $e');
    }
  }

  Future<void> testNotifications() async {
    if (!notificationsInitialized) {
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
            content: Text('Notification de test envoyée !'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('Erreur test notifications: $e');
    }
  }

  Future<void> fetchUserEvaluations() async {
    if (userProfile.id == null) return;

    setState(() {
      isLoadingEvaluations = true;
      evaluationError = null;
    });

    try {
      if (Platform.isIOS) {
        await fetchUserEvaluationsIOS();
      } else {
        await fetchUserEvaluationsAndroid();
      }
    } catch (e) {
      setState(() {
        evaluationError = 'Erreur: ${e.toString()}';
        isLoadingEvaluations = false;
        upcomingEvaluations = [];
        evaluationSummary = null;
        showEvaluations = false;
      });
    }
  }

  Future<void> fetchUserEvaluationsIOS() async {
    try {
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
      setState(() {
        evaluationError = 'Erreur iOS: ${e.toString()}';
        isLoadingEvaluations = false;
      });
    }
  }

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
              }
            } catch (parseError) {
              throw parseError;
            }
          }
        }
      } catch (e) {
        throw e;
      }
    }
  }

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
                  const Text(
                    'Mes évaluations',
                    style: TextStyle(
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
        if (tokenRetrieved) {
          _checkBackgroundReminders();
        }
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: controller),
            if (isLoading)
              const Center(child: CircularProgressIndicator()),
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
                        style: const TextStyle(color: Colors.white, fontSize: 10),
                      ),
                    ],
                  ),
                ),
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
