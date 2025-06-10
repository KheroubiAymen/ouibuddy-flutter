import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'evaluation_service.dart';
import 'evaluation_widgets.dart';
import 'evaluation_scheduler.dart';
import 'BackgroundNotificationService.dart'; // NOUVEAU IMPORT
import 'dart:convert';
import 'package:flutter/services.dart';
import 'dart:async';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser les notifications
  await NotificationService.initialize();

  // NOUVEAU : Initialiser le service de rappels automatiques
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
      home: const WebViewPage(),
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
  bool wasInBackground = false;
  DateTime? lastBackgroundTime;
  bool hasError = false;
  int retryCount = 0;
  String? sessionToken;
  UserProfile userProfile = UserProfile.loading();
  bool notificationsInitialized = false;
  bool isCheckingAuth = false;
  List<Evaluation> upcomingEvaluations = [];
  EvaluationSummary? evaluationSummary;
  bool isLoadingEvaluations = false;
  String? evaluationError;
  bool showEvaluations = false;

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    initController();
    WidgetsBinding.instance.addObserver(this);

    // NOUVEAU : Vérifier les rappels au démarrage
    _checkBackgroundReminders();
  }

  // NOUVELLE méthode : Vérifier les rappels au démarrage
  Future<void> _checkBackgroundReminders() async {
    // Attendre que l'utilisateur soit connecté
    await Future.delayed(const Duration(seconds: 10));

    if (userProfile.id != null && upcomingEvaluations.isNotEmpty) {
      await BackgroundNotificationService.checkAndReschedule(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );
    }
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

            // Démarrer la surveillance des URLs
            monitorUrlChanges();

            // Délai pour laisser la page se charger complètement
            Future.delayed(const Duration(seconds: 3), () {
              extractSessionAndProfile();
            });

            // Si on est sur le dashboard, essayer une extraction supplémentaire
            if (url.contains('/dashboard') || url.contains('/profile')) {
              Future.delayed(const Duration(seconds: 5), () {
                print('🎯 Page dashboard détectée, extraction supplémentaire...');
                extractSessionAndProfile();
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
      userProfile = UserProfile.loading();
      sessionToken = null;
      isCheckingAuth = false;
    });
    controller.reload();
  }

  // Surveiller les changements d'URL
  Future<void> monitorUrlChanges() async {
    try {
      await controller.runJavaScript('''
        let lastUrl = window.location.href;
        
        setInterval(function() {
          if (window.location.href !== lastUrl) {
            lastUrl = window.location.href;
            console.log('🔄 URL changée:', lastUrl);
            
            if (lastUrl.includes('/dashboard') || lastUrl.includes('/profile')) {
              console.log('📍 Sur une page authentifiée, extraction du profil...');
              setTimeout(function() {
                console.log('🔍 Tentative extraction profil après navigation');
              }, 2000);
            }
          }
        }, 1000);
      ''');
    } catch (e) {
      print('❌ Erreur surveillance URL: $e');
    }
  }

  // Méthode principale pour extraire session et profil
  Future<void> extractSessionAndProfile() async {
    if (isCheckingAuth) {
      print('⚠️ Vérification d\'authentification déjà en cours...');
      return;
    }

    setState(() {
      isCheckingAuth = true;
    });

    try {
      print('🔍 === DÉBUT EXTRACTION SESSION ET PROFIL ===');

      // 1. Vérifier l'authentification via les cookies de session Laravel
      final sessionInfo = await extractLaravelSession();
      print('🍪 Session Laravel: ${sessionInfo != null}');

      // 2. Vérifier le statut d'authentification
      final isAuth = await checkAuthenticationStatus();
      print('🔐 Statut authentification: $isAuth');

      // 3. Récupérer le profil utilisateur si authentifié
      if (isAuth) {
        print('✅ Utilisateur authentifié, récupération du profil...');

        // Essayer l'API en premier
        await fetchUserProfileViaWebView();

        // Si pas de profil récupéré via API, essayer l'extraction depuis l'URL
        if (userProfile.id == null || userProfile.loading) {
          print('🔄 API pas de résultat, extraction depuis URL...');
          await extractProfileFromUrl();
        }
      } else {
        print('⚠️ Utilisateur non authentifié');

        // Même si pas authentifié officiellement, essayer l'extraction URL si on est sur dashboard
        final url = await controller.runJavaScriptReturningResult('window.location.href');
        if (url != null && url.toString().contains('/dashboard')) {
          print('🎯 Sur dashboard sans auth détectée, extraction URL...');
          await extractProfileFromUrl();
        } else {
          setState(() {
            userProfile = UserProfile.notAuthenticated();
          });
          await suggestLogin();
        }
      }

      // Log final du statut
      print('📋 RÉSULTAT FINAL: ${userProfile.firstName} (ID: ${userProfile.id}, Auth: ${userProfile.isAuthenticated})');

    } catch (e) {
      print('❌ Erreur lors de l\'extraction: $e');
      // Dernière tentative avec l'URL
      await extractProfileFromUrl();
    } finally {
      setState(() {
        isCheckingAuth = false;
      });
    }
  }

  // Méthode pour extraire les informations de session Laravel
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
            
            sessionInfo.hasActiveSession = sessionInfo.laravel_session && 
                                          (sessionInfo.xsrf_token || sessionInfo.csrf_token);
            
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
        print('🍪 Données session parsées: $sessionData');

        if (sessionData['hasActiveSession'] == true) {
          sessionToken = sessionData['laravel_session'];
          return sessionData;
        }
      }

      return null;
    } catch (e) {
      print('❌ Erreur extraction session Laravel: $e');
      return await extractSimpleCookies();
    }
  }

  // Méthode de fallback pour extraire les cookies simplement
  Future<Map<String, dynamic>?> extractSimpleCookies() async {
    try {
      print('🔍 Extraction simple des cookies...');

      final cookies = await controller.runJavaScriptReturningResult('document.cookie');
      final csrfToken = await controller.runJavaScriptReturningResult(
          'document.querySelector(\'meta[name="csrf-token"]\')?.getAttribute(\'content\') || null'
      );

      if (cookies != null) {
        final cookieString = cookies.toString().replaceAll('"', '');
        final csrfString = csrfToken?.toString().replaceAll('"', '');

        bool hasLaravelSession = cookieString.contains('laravel_session');
        bool hasXSRF = cookieString.contains('XSRF-TOKEN');

        if (hasLaravelSession || hasXSRF || csrfString != null) {
          return {
            'hasActiveSession': true,
            'hasLaravelSession': hasLaravelSession,
            'hasXSRF': hasXSRF,
            'hasCSRF': csrfString != null,
            'cookies': cookieString
          };
        }
      }

      return null;
    } catch (e) {
      print('❌ Erreur extraction simple: $e');
      return null;
    }
  }

  // Méthode pour vérifier l'authentification
  Future<bool> checkAuthenticationStatus() async {
    try {
      print('🔍 Vérification du statut d\'authentification...');

      final result = await controller.runJavaScriptReturningResult('''
        (function() {
          try {
            const checks = {
              currentUrl: window.location.href,
              hasLaravelSession: document.cookie.includes('laravel_session'),
              hasXSRFToken: document.cookie.includes('XSRF-TOKEN'),
              hasCSRFToken: document.querySelector('meta[name="csrf-token"]') !== null,
              hasUserElements: document.querySelector('.user-info, .profile-info, [data-user], .logout-btn, .dashboard, .user-dropdown') !== null,
              isOnPrivatePage: window.location.href.includes('/dashboard') ||
                              window.location.href.includes('/profile') ||
                              window.location.href.includes('/admin') ||
                              window.location.href.includes('/user'),
              isOnLoginPage: window.location.href.includes('/login') ||
                            window.location.href.includes('/auth') ||
                            document.querySelector('form[action*="login"], input[name="email"][type="email"]') !== null,
              cookiesCount: document.cookie.split(';').filter(c => c.trim()).length,
              hasUserIdInUrl: /\\/\\d+\\//.test(window.location.pathname)
            };
            
            const isAuthenticated = (
              checks.hasLaravelSession || 
              checks.hasXSRFToken || 
              checks.hasCSRFToken || 
              checks.isOnPrivatePage ||
              checks.hasUserIdInUrl
            ) && !checks.isOnLoginPage;
            
            return JSON.stringify({
              ...checks,
              isAuthenticated: isAuthenticated
            });
          } catch (error) {
            return JSON.stringify({
              error: error.message,
              isAuthenticated: false
            });
          }
        })()
      ''');

      if (result != null) {
        String cleanResult = result.toString();

        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }

        cleanResult = cleanResult.replaceAll('\\"', '"');
        cleanResult = cleanResult.replaceAll('\\\\', '\\');

        final authStatus = json.decode(cleanResult);
        return authStatus['isAuthenticated'] == true;
      }

      return false;
    } catch (e) {
      print('❌ Erreur vérification authentification: $e');
      return await checkSimpleAuthentication();
    }
  }

  // Méthode de fallback pour vérifier l'authentification
  Future<bool> checkSimpleAuthentication() async {
    try {
      final url = await controller.runJavaScriptReturningResult('window.location.href');
      final pathname = await controller.runJavaScriptReturningResult('window.location.pathname');

      if (url != null && pathname != null) {
        final urlString = url.toString().replaceAll('"', '');
        final pathString = pathname.toString().replaceAll('"', '');

        bool onDashboard = urlString.contains('/dashboard');
        bool hasIdInPath = RegExp(r'/\d+/').hasMatch(pathString);
        bool notOnLogin = !urlString.contains('/login');

        bool isAuth = onDashboard && hasIdInPath && notOnLogin;
        return isAuth;
      }

      return false;
    } catch (e) {
      print('❌ Erreur auth simple: $e');
      return false;
    }
  }

  // Récupérer le profil utilisateur via WebView avec l'API Laravel
  Future<void> fetchUserProfileViaWebView() async {
    try {
      print('🔍 Récupération profil via API WebView...');

      final result = await controller.runJavaScriptReturningResult('''
        (async function() {
          try {
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
            
            if (!csrfToken) {
              return JSON.stringify({
                success: false,
                error: 'Token CSRF manquant',
                needsRefresh: true
              });
            }
            
            const response = await fetch('/profile/connected/basic', {
              method: 'GET',
              headers: {
                'X-CSRF-TOKEN': csrfToken,
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'X-Requested-With': 'XMLHttpRequest'
              },
              credentials: 'same-origin'
            });
            
            if (response.ok) {
              const data = await response.json();
              return JSON.stringify({
                success: true,
                data: data,
                status: response.status
              });
            } else {
              const errorText = await response.text();
              return JSON.stringify({
                success: false,
                status: response.status,
                error: errorText,
                needsLogin: response.status === 401
              });
            }
          } catch (error) {
            return JSON.stringify({
              success: false,
              error: error.message,
              networkError: true
            });
          }
        })()
      ''');

      if (result != null && result.toString() != 'null') {
        await handleApiResponse(result.toString());
      } else {
        print('❌ Pas de résultat de l\'API');
      }
    } catch (e) {
      print('❌ Erreur récupération profil: $e');
    }
  }

  // Extraire le profil depuis l'URL
  Future<void> extractProfileFromUrl() async {
    try {
      print('🔍 Extraction profil depuis URL...');

      final result = await controller.runJavaScriptReturningResult('''
        (function() {
          const profile = {
            id: null,
            first_name: 'Utilisateur',
            extracted_from: 'url'
          };
          
          const urlMatch = window.location.pathname.match(/\\/(\\d+)\\//);
          if (urlMatch) {
            profile.id = parseInt(urlMatch[1]);
          }
          
          const textContent = document.body.innerText || document.body.textContent || '';
          
          const namePatterns = [
            /Bonjour\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Salut\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Hello\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Hi\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Bienvenue\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Welcome\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Connecté\\s+en\\s+tant\\s+que\\s+([A-Za-zÀ-ÿ]{2,})/i,
            /Logged\\s+in\\s+as\\s+([A-Za-zÀ-ÿ]{2,})/i
          ];
          
          for (const pattern of namePatterns) {
            const match = textContent.match(pattern);
            if (match && match[1] && match[1].length > 1) {
              profile.first_name = match[1];
              break;
            }
          }
          
          const nameSelectors = [
            '.user-name',
            '.username', 
            '.profile-name',
            '#user-name',
            '[data-user-name]',
            '.greeting',
            '.welcome-message',
            '.user-greeting'
          ];
          
          for (const selector of nameSelectors) {
            const element = document.querySelector(selector);
            if (element && element.textContent && element.textContent.trim()) {
              const text = element.textContent.trim();
              const nameMatch = text.match(/([A-Za-zÀ-ÿ]{2,})/);
              if (nameMatch && nameMatch[1] && nameMatch[1].length > 1) {
                profile.first_name = nameMatch[1];
                break;
              }
            }
          }
          
          return JSON.stringify(profile);
        })()
      ''');

      if (result != null && result.toString() != 'null') {
        String cleanResult = result.toString();

        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }

        cleanResult = cleanResult.replaceAll('\\"', '"');
        cleanResult = cleanResult.replaceAll('\\\\', '\\');

        try {
          final profileData = json.decode(cleanResult);
          print('👤 Profil extrait de l\'URL: $profileData');

          if (profileData['id'] != null) {
            setState(() {
              userProfile = UserProfile(
                id: profileData['id'],
                firstName: profileData['first_name'] ?? 'Utilisateur',
                isAuthenticated: true,
                loading: false,
              );
            });

            print('✅ PROFIL CRÉÉ: ${userProfile.firstName} (ID: ${userProfile.id})');

            if (userProfile.id != null) {
              await sendWelcomeNotification();
            }
          }
        } catch (e) {
          print('❌ Erreur parsing profil URL: $e');
        }
      }
    } catch (e) {
      print('❌ Erreur extraction profil URL: $e');
    }
  }

  // Gérer la réponse API
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

          print('✅ PROFIL RÉCUPÉRÉ VIA API: ${userProfile.firstName} (ID: ${userProfile.id})');

          if (userProfile.id != null) {
            await sendWelcomeNotification();
          }
        } else {
          await handleApiError(apiData);
        }
      } else {
        await handleApiError(response);
      }
    } catch (parseError) {
      print('❌ Erreur parsing: $parseError');
    }
  }

  // Gérer les erreurs API
  Future<void> handleApiError(Map<String, dynamic> response) async {
    final status = response['status'];

    if (status == 401 || response['needsLogin'] == true) {
      print('🔒 Non authentifié - extraction URL en fallback');
      await extractProfileFromUrl();
    } else if (response['needsRefresh'] == true) {
      print('🔄 Page doit être rafraîchie');
      await refreshPageAndRetry();
    } else {
      print('❌ Erreur API: ${response['error']}');
      await extractProfileFromUrl();
    }
  }

  // Rafraîchir et réessayer
  Future<void> refreshPageAndRetry() async {
    print('🔄 Rafraîchissement de la page...');
    await controller.reload();
    await Future.delayed(const Duration(seconds: 3));
    await extractSessionAndProfile();
  }

  // Suggérer à l'utilisateur de se connecter
  Future<void> suggestLogin() async {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('🔒 Vous devez vous connecter pour accéder à votre profil'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 5),
          action: SnackBarAction(
            label: 'Se connecter',
            onPressed: () async {
              await controller.runJavaScript('''
                if (window.location.href !== 'https://ouibuddy.com/login') {
                  window.location.href = 'https://ouibuddy.com/login';
                }
              ''');
            },
          ),
        ),
      );
    }
  }

  // Méthode d'envoi de notification de bienvenue
  Future<void> sendWelcomeNotification() async {
    if (!notificationsInitialized || userProfile.id == null) {
      print('⚠️ Notifications non autorisées ou pas d\'utilisateur');
      return;
    }

    try {
      print('📱 Envoi notification système de bienvenue...');

      // Envoyer la notification système de bienvenue
      await NotificationService.showWelcomeNotification(
        userProfile.firstName,
        userProfile.id!,
      );

      // Récupérer les évaluations après la notification de bienvenue
      await Future.delayed(const Duration(seconds: 2));
      await fetchUserEvaluations();

      // NOUVEAU : Programmer et envoyer les notifications d'évaluations
      await Future.delayed(const Duration(seconds: 1));
      await scheduleEvaluationNotifications();

      // Afficher aussi un SnackBar dans l'app
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 Bienvenue ${userProfile.firstName} ! Notifications programmées ✅'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Voir évaluations',
              onPressed: () => _showEvaluationsBottomSheet(),
            ),
          ),
        );
      }

      print('✅ Notification système envoyée et évaluations notifiées');

    } catch (e) {
      print('❌ Erreur envoi notification: $e');
    }
  }

  // Méthode de test des notifications
  Future<void> testNotifications() async {
    if (!notificationsInitialized) {
      print('❌ Notifications non autorisées');
      _showNotificationPermissionDialog();
      return;
    }

    try {
      await NotificationService.showTestNotification(userProfile.firstName);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('📱 Notification de test envoyée !'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur test notifications: $e');
    }
  }

  // Forcer la vérification du profil
  Future<void> forceProfileCheck() async {
    setState(() {
      userProfile = UserProfile.loading();
      isCheckingAuth = false;
    });

    await extractSessionAndProfile();
  }

  // MODIFIÉE : Méthode pour programmer les notifications automatiques
  Future<void> scheduleEvaluationNotifications() async {
    if (!notificationsInitialized || userProfile.id == null) {
      print('⚠️ Conditions non réunies pour programmer les notifications');
      return;
    }

    try {
      print('⏰ Programmation des notifications d\'évaluations...');

      // Utiliser EvaluationScheduler pour programmer les rappels
      await EvaluationScheduler.performDailyEvaluationCheck(
        controller,
        userProfile.id,
      );

      // NOUVEAU : Programmer les rappels automatiques toutes les 5 minutes
      await BackgroundNotificationService.scheduleFromEvaluations(
        userProfile.firstName,
        userProfile.id!,
        upcomingEvaluations,
      );

      // Envoyer immédiatement les notifications pour les évaluations urgentes
      await notifyUrgentEvaluations();

      print('✅ Notifications programmées avec succès (incluant rappels automatiques)');

    } catch (e) {
      print('❌ Erreur programmation notifications: $e');
    }
  }

  // NOUVELLE méthode : Afficher le statut des rappels
  Future<void> _showReminderStatus() async {
    try {
      final status = await BackgroundNotificationService.getReminderStatus();

      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('📱 Statut des rappels automatiques'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Total notifications: ${status['total_pending']}'),
                Text('Rappels 5min: ${status['periodic_reminders']}'),
                Text('Reprogrammation: ${status['has_reprogramming'] ? "✅" : "❌"}'),
                if (status['next_reminder'] != null)
                  Text('Prochain: ${status['next_reminder']}'),
                if (status['error'] != null)
                  Text('Erreur: ${status['error']}', style: const TextStyle(color: Colors.red)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await BackgroundNotificationService.cancelPeriodicReminders();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🚫 Rappels automatiques annulés'),
                      backgroundColor: Colors.red,
                    ),
                  );
                },
                child: const Text('🚫 Arrêter rappels'),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  if (userProfile.id != null && upcomingEvaluations.isNotEmpty) {
                    await BackgroundNotificationService.scheduleFromEvaluations(
                      userProfile.firstName,
                      userProfile.id!,
                      upcomingEvaluations,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🔄 Rappels automatiques reprogrammés'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('🔄 Reprogrammer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      print('❌ Erreur affichage statut: $e');
    }
  }

  // MODIFIÉE : Gestionnaire du cycle de vie de l'app
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.resumed:
        print('📱 App reprise - vérification des rappels');
        _checkBackgroundReminders();
        break;
      case AppLifecycleState.paused:
        print('📱 App en pause - rappels automatiques continuent');
        break;
      case AppLifecycleState.detached:
        print('📱 App fermée - rappels automatiques actifs');
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
      appBar: AppBar(
        title: Row(
          children: [
            const Text('OuiBuddy'),
            if (!userProfile.loading && userProfile.id != null) ...[
              const Text(' - '),
              Text(
                userProfile.firstName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue,
                ),
              ),
            ],
          ],
        ),
        backgroundColor: Colors.blue.shade50,
        actions: [
          IconButton(
            icon: Icon(
              Icons.refresh,
              color: isCheckingAuth ? Colors.orange : Colors.blue,
            ),
            onPressed: isCheckingAuth ? null : forceProfileCheck,
            tooltip: 'Vérifier profil',
          ),

          // Bouton évaluations
          if (userProfile.id != null)
            IconButton(
              icon: Stack(
                children: [
                  Icon(
                    Icons.assignment,
                    color: showEvaluations ? Colors.green : Colors.blue,
                  ),
                  if (upcomingEvaluations.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          upcomingEvaluations.length.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () {
                if (showEvaluations) {
                  _showEvaluationsBottomSheet();
                } else {
                  fetchUserEvaluations();
                }
              },
              tooltip: showEvaluations ? 'Voir évaluations' : 'Charger évaluations',
            ),

          // Bouton pour notifier les évaluations urgentes
          if (userProfile.id != null && upcomingEvaluations.isNotEmpty)
            IconButton(
              icon: Stack(
                children: [
                  const Icon(Icons.notification_important, color: Colors.red),
                  if (upcomingEvaluations.any((e) => e.isToday || e.isTomorrow))
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: const Text(
                          '!',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              onPressed: () async {
                await notifyUrgentEvaluations();
              },
              tooltip: 'Notifier évaluations urgentes',
            ),

          // NOUVEAU bouton pour gérer les rappels automatiques
          if (userProfile.id != null)
            IconButton(
              icon: const Icon(Icons.autorenew, color: Colors.teal),
              onPressed: () => _showReminderStatus(),
              tooltip: 'Rappels automatiques',
            ),

          // Bouton notifications générales
          IconButton(
            icon: Icon(
              Icons.notifications,
              color: notificationsInitialized ? Colors.green : Colors.red,
            ),
            onPressed: () async {
              if (notificationsInitialized) {
                await testNotifications();
              } else {
                _showNotificationPermissionDialog();
              }
            },
            tooltip: notificationsInitialized
                ? 'Test notifications'
                : 'Activer notifications',
          ),

          // Bouton test complet
          if (userProfile.id != null)
            IconButton(
              icon: const Icon(Icons.science, color: Colors.purple),
              onPressed: () async {
                if (notificationsInitialized) {
                  await NotificationService.runFullTest(
                      userProfile.firstName,
                      userProfile.id!
                  );

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('🧪 Test complet lancé ! Vérifiez vos notifications'),
                        backgroundColor: Colors.purple,
                      ),
                    );
                  }
                }
              },
              tooltip: 'Test complet notifications',
            ),

          // Bouton profil utilisateur
          if (userProfile.id != null)
            IconButton(
              icon: const Icon(Icons.person, color: Colors.green),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('👤 Profil Utilisateur'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Prénom: ${userProfile.firstName}'),
                        if (userProfile.lastName != null)
                          Text('Nom: ${userProfile.lastName}'),
                        if (userProfile.email != null)
                          Text('Email: ${userProfile.email}'),
                        Text('ID: ${userProfile.id}'),
                        if (userProfile.userId != null)
                          Text('User ID: ${userProfile.userId}'),
                        const SizedBox(height: 10),
                        Text('Session: ${sessionToken != null ? "✅ Active" : "❌ Inactive"}'),
                        Text('Authentifié: ${userProfile.isAuthenticated ? "✅ Oui" : "❌ Non"}'),
                        Text('Notifications: ${notificationsInitialized ? "✅ Actives" : "❌ Inactives"}'),
                        Text('Évaluations: ${upcomingEvaluations.length} à venir'),
                        if (upcomingEvaluations.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            'Urgentes: ${upcomingEvaluations.where((e) => e.isToday || e.isTomorrow).length}',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ],
                    ),
                    actions: [
                      if (upcomingEvaluations.isNotEmpty)
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await notifyUrgentEvaluations();
                          },
                          child: const Text('🚨 Notifier urgentes'),
                        ),
                      TextButton(
                        onPressed: () => fetchUserEvaluations(),
                        child: const Text('📚 Recharger évaluations'),
                      ),
                      TextButton(
                        onPressed: () => sendWelcomeNotification(),
                        child: const Text('📱 Test Notification'),
                      ),
                      TextButton(
                        onPressed: () => forceProfileCheck(),
                        child: const Text('🔄 Recharger Profil'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              tooltip: 'Profil utilisateur',
            ),
        ],
      ),

      body: Stack(
        children: [
          WebViewWidget(controller: controller),

          if (isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),

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

          if (isCheckingAuth)
            Positioned(
              top: 10,
              left: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Vérification...',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // Floating Action Button pour les évaluations
          if (showEvaluations && upcomingEvaluations.isNotEmpty)
            Positioned(
              bottom: 100,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _showEvaluationsBottomSheet,
                backgroundColor: Colors.orange,
                icon: const Icon(Icons.assignment, color: Colors.white),
                label: Text(
                  '${upcomingEvaluations.length} éval.',
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),

          // Floating Action Button pour notifications urgentes
          if (showEvaluations && upcomingEvaluations.any((e) => e.isToday || e.isTomorrow))
            Positioned(
              bottom: 160,
              right: 20,
              child: FloatingActionButton(
                onPressed: () async {
                  await notifyUrgentEvaluations();
                },
                backgroundColor: Colors.red,
                child: const Icon(Icons.notification_important, color: Colors.white),
                tooltip: 'Notifier évaluations urgentes',
              ),
            ),

          // Widget profil en bas
          if (!userProfile.loading)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: userProfile.isAuthenticated
                      ? Colors.green
                      : (userProfile.id != null ? Colors.orange : Colors.red),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (userProfile.id != null) ...[
                      Text(
                        '👤 ${userProfile.firstName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'ID: ${userProfile.id} • Auth: ${userProfile.isAuthenticated ? "✅" : "❌"}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      if (upcomingEvaluations.isNotEmpty) ...[
                        Text(
                          '📚 ${upcomingEvaluations.length} évaluations à venir',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                          ),
                        ),
                        if (upcomingEvaluations.any((e) => e.isToday || e.isTomorrow))
                          Text(
                            '🚨 ${upcomingEvaluations.where((e) => e.isToday || e.isTomorrow).length} urgentes !',
                            style: const TextStyle(
                              color: Colors.yellow,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                      ],
                    ] else ...[
                      Text(
                        '👤 ${userProfile.firstName}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    if (sessionToken != null) ...[
                      const SizedBox(height: 4),
                      const Text(
                        '🍪 Session active',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // MODIFIÉE : Récupération des évaluations avec programmation automatique
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

          if (debug['status'] == 'success' && debug['hasData'] == true) {
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

                // NOUVEAU : Programmer automatiquement les rappels après récupération
                if (evaluations.isNotEmpty && userProfile.id != null && notificationsInitialized) {
                  await BackgroundNotificationService.scheduleFromEvaluations(
                    userProfile.firstName,
                    userProfile.id!,
                    evaluations,
                  );
                  print('🔄 Rappels automatiques mis à jour avec ${evaluations.length} évaluations');
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✅ ${evaluations.length} évaluations trouvées !'),
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
            content: Text('📱 ${urgentEvaluations.length} notifications envoyées pour les évaluations urgentes'),
            backgroundColor: urgentEvaluations.any((e) => e.isToday) ? Colors.red : Colors.orange,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Voir',
              onPressed: () => _showEvaluationsBottomSheet(),
            ),
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}