import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
// import 'package:url_launcher/url_launcher.dart'; // ← COMMENTEZ CETTE LIGNE

import 'evaluation_service.dart';
import 'evaluation_widgets.dart';
import 'evaluation_scheduler.dart';
import 'BackgroundNotificationService.dart'; // NOUVEAU IMPORT
import 'dart:convert';
import 'package:flutter/services.dart';
import 'splash_screen.dart';
import 'dart:async';
import 'notification_service.dart';
import 'dart:io'; // AJOUTÉ pour Platform.isIOS

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
      home: const SplashScreen(), // ← CHANGER CETTE LIGNE (était WebViewPage())
      routes: {
        '/home': (context) => const WebViewPage(), // ← AJOUTER CETTE LIGNE
      },
      debugShowCheckedModeBanner:
          false, // ← OPTIONNEL : masquer le banner debug
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
              'veuillez autoriser les notifications dans les paramètres de votre appareil.'),
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
            print(
                '🌐 [${Platform.isIOS ? "iOS" : "Android"}] Page starting: $url');
          },
          onPageFinished: (url) {
            setState(() {
              isLoading = false;
            });
            print(
                '✅ [${Platform.isIOS ? "iOS" : "Android"}] Page finished: $url');

            // Délais adaptés selon la plateforme
            final delay = Platform.isIOS
                ? const Duration(seconds: 6)
                : const Duration(seconds: 3);

            Future.delayed(delay, () {
              if (Platform.isIOS) {
                monitorUrlChangesIOS();
              } else {
                monitorUrlChanges();
              }
              extractSessionAndProfile();
            });

            // Dashboard check avec délai plus long pour iOS
            if (url.contains('/dashboard') || url.contains('/profile')) {
              final dashboardDelay = Platform.isIOS
                  ? const Duration(seconds: 8)
                  : const Duration(seconds: 5);

              Future.delayed(dashboardDelay, () {
                print(
                    '🎯 [${Platform.isIOS ? "iOS" : "Android"}] Dashboard détecté, extraction supplémentaire...');
                extractSessionAndProfile();
              });
            }
          },
          onWebResourceError: (error) {
            print(
                '❌ [${Platform.isIOS ? "iOS" : "Android"}] Web resource error: ${error.errorCode} - ${error.description}');

            // Gestion d'erreur adaptée iOS
            if (Platform.isIOS) {
              // iOS peut avoir des erreurs différentes
              if (error.errorCode == -1 ||
                  error.errorCode == -999 || // NSURLErrorCancelled sur iOS
                  error.description.contains('cancelled') ||
                  error.description.contains('ERR_CACHE_MISS')) {
                if (retryCount < 5) {
                  // Plus de tentatives sur iOS
                  retryCount++;
                  print('🔄 [iOS] Retry attempt $retryCount');
                  Future.delayed(const Duration(seconds: 2), () {
                    reloadPage();
                  });
                } else {
                  setState(() {
                    hasError = true;
                    isLoading = false;
                  });
                }
              }
            } else {
              // Logique Android existante
              if (error.errorCode == -1 ||
                  error.description.contains('ERR_CACHE_MISS')) {
                if (retryCount < 3) {
                  retryCount++;
                  print('🔄 [Android] Retry attempt $retryCount');
                  reloadPage();
                } else {
                  setState(() {
                    hasError = true;
                    isLoading = false;
                  });
                }
              }
            }
          },
          onNavigationRequest: (request) {
            print(
                '🧭 [${Platform.isIOS ? "iOS" : "Android"}] Navigation vers: ${request.url}');
            if (!request.url.startsWith('https://ouibuddy.com')) {
              print(
                  '🔗 [TEMPORAIRE] URL externe bloquée pour éviter crash: ${request.url}'); // ← AJOUTEZ CECI
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

  // Surveillance URL adaptée iOS
  Future<void> monitorUrlChangesIOS() async {
    try {
      print('🍎 [iOS] Surveillance URL simplifiée...');

      await controller.runJavaScript('''
        (function() {
          try {
            var lastUrl = window.location.href;
            
            // Version simplifiée pour iOS
            setInterval(function() {
              var currentUrl = window.location.href;
              if (currentUrl !== lastUrl) {
                lastUrl = currentUrl;
                console.log('[iOS] URL changée:', lastUrl);
                
                if (lastUrl.indexOf('/dashboard') !== -1 || lastUrl.indexOf('/profile') !== -1) {
                  console.log('[iOS] Sur une page authentifiée');
                }
              }
            }, 2000); // Intervalle plus long sur iOS
            
          } catch (error) {
            console.log('[iOS] Erreur surveillance URL:', error.message);
          }
        })();
      ''');
    } catch (e) {
      print('❌ [iOS] Erreur surveillance URL: $e');
    }
  }

  // MODIFIÉE : Méthode principale pour extraire session et profil avec navigation automatique
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
      print('📱 Plateforme détectée: ${Platform.isIOS ? "iOS" : "Android"}');

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

        // Si profil récupéré avec succès, vérifier la navigation
        if (userProfile.id != null &&
            !userProfile.loading &&
            userProfile.firstName != 'Utilisateur') {
          print(
              '🎯 Profil récupéré avec succès: ${userProfile.firstName} (ID: ${userProfile.id})');

          // NOUVEAU : Vérifier et naviguer vers le dashboard
          await checkAndNavigateToDashboard();
        } else {
          print('🔄 API pas de résultat, extraction depuis URL...');
          await extractProfileFromUrl();
        }
      } else {
        print('⚠️ Utilisateur non authentifié');

        // Même si pas authentifié officiellement, essayer l'extraction URL si on est sur dashboard
        final url = await controller
            .runJavaScriptReturningResult('window.location.href');
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
      print(
          '📋 RÉSULTAT FINAL: ${userProfile.firstName} (ID: ${userProfile.id}, Auth: ${userProfile.isAuthenticated})');
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

  // NOUVELLE MÉTHODE : Vérifier et naviguer vers le dashboard
  Future<void> checkAndNavigateToDashboard() async {
    try {
      print('🔍 Vérification navigation dashboard...');

      // Récupérer l'URL actuelle
      final currentUrlResult =
          await controller.runJavaScriptReturningResult('window.location.href');
      final currentUrl = currentUrlResult?.toString().replaceAll('"', '') ?? '';

      print('🌐 URL actuelle: $currentUrl');

      // Si on n'est pas sur le dashboard et qu'on a un utilisateur connecté
      if (!currentUrl.contains('/dashboard') && userProfile.id != null) {
        print('🚀 Utilisateur connecté mais pas sur dashboard, navigation...');

        // CORRECTION : Format correct de l'URL {id}/dashboard
        final dashboardUrl = 'https://ouibuddy.com/${userProfile.id}/dashboard';
        print('🎯 Navigation vers: $dashboardUrl');

        // Naviguer vers le dashboard
        await controller.loadRequest(Uri.parse(dashboardUrl));

        // Attendre que la page se charge
        await Future.delayed(const Duration(seconds: 3));

        // Vérifier si la navigation a réussi
        final newUrlResult = await controller
            .runJavaScriptReturningResult('window.location.href');
        final newUrl = newUrlResult?.toString().replaceAll('"', '') ?? '';

        if (newUrl.contains('/dashboard')) {
          print('✅ Navigation dashboard réussie: $newUrl');

          // Envoyer la notification de bienvenue maintenant
          if (userProfile.id != null) {
            await sendWelcomeNotification();
          }
        } else {
          print('❌ Échec navigation dashboard, URL: $newUrl');

          // Tentative de navigation JavaScript
          await forceNavigationToDashboard();
        }
      } else if (currentUrl.contains('/dashboard')) {
        print('✅ Déjà sur le dashboard');

        // Envoyer la notification de bienvenue
        if (userProfile.id != null) {
          await sendWelcomeNotification();
        }
      } else {
        print('⚠️ Pas d\'utilisateur connecté pour naviguer');
      }
    } catch (e) {
      print('❌ Erreur vérification navigation: $e');
    }
  }

  // MÉTHODE DE SECOURS : Forcer la navigation via JavaScript
  Future<void> forceNavigationToDashboard() async {
    try {
      print('🔧 Tentative navigation JavaScript...');

      await controller.runJavaScript('''
        (function() {
          try {
            var dashboardUrl = 'https://ouibuddy.com/${userProfile.id}/dashboard';
            console.log('🚀 Navigation JavaScript vers:', dashboardUrl);
            
            // Essayer plusieurs méthodes de navigation
            if (window.location) {
              window.location.href = dashboardUrl;
            } else {
              window.location.replace(dashboardUrl);
            }
            
          } catch (error) {
            console.log('❌ Erreur navigation JavaScript:', error.message);
          }
        })()
      ''');

      print('✅ Script de navigation JavaScript exécuté');
    } catch (e) {
      print('❌ Erreur navigation JavaScript: $e');
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

      final cookies =
          await controller.runJavaScriptReturningResult('document.cookie');
      final csrfToken = await controller.runJavaScriptReturningResult(
          'document.querySelector(\'meta[name="csrf-token"]\')?.getAttribute(\'content\') || null');

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

  // MODIFIÉE : Méthode pour vérifier l'authentification avec bon format URL
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
              // CORRECTION : Vérifier le bon format d'URL dashboard
              isOnPrivatePage: window.location.href.includes('/dashboard') ||
                              window.location.href.includes('/profile') ||
                              window.location.href.includes('/admin') ||
                              /\\/\\d+\\/dashboard/.test(window.location.pathname) ||  // Format {id}/dashboard
                              /\\/\\d+\\/profile/.test(window.location.pathname),     // Format {id}/profile
              isOnLoginPage: window.location.href.includes('/login') ||
                            window.location.href.includes('/auth') ||
                            document.querySelector('form[action*="login"], input[name="email"][type="email"]') !== null,
              cookiesCount: document.cookie.split(';').filter(c => c.trim()).length,
              hasUserIdInUrl: /\\/\\d+\\//.test(window.location.pathname)  // Détecte /{id}/
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
        print('🔐 Auth status détails: $authStatus');
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
      final url =
          await controller.runJavaScriptReturningResult('window.location.href');
      final pathname = await controller
          .runJavaScriptReturningResult('window.location.pathname');

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

      // Version iOS-compatible : utiliser XMLHttpRequest synchrone au lieu de fetch async
      final result = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          // 1. Récupérer le token CSRF
          var csrfToken = document.querySelector('meta[name="csrf-token"]');
          if (!csrfToken) {
            return JSON.stringify({
              success: false,
              error: 'Token CSRF manquant',
              needsRefresh: true
            });
          }
          
          var tokenValue = csrfToken.getAttribute('content');
          if (!tokenValue) {
            return JSON.stringify({
              success: false,
              error: 'Token CSRF vide',
              needsRefresh: true
            });
          }
          
          // 2. Utiliser XMLHttpRequest SYNCHRONE (compatible iOS)
          var xhr = new XMLHttpRequest();
          
          // Configuration de la requête
          xhr.open('GET', '/profile/connected/basic', false); // false = synchrone
          xhr.setRequestHeader('X-CSRF-TOKEN', tokenValue);
          xhr.setRequestHeader('Accept', 'application/json');
          xhr.setRequestHeader('Content-Type', 'application/json');
          xhr.setRequestHeader('X-Requested-With', 'XMLHttpRequest');
          
          // 3. Envoyer la requête
          try {
            xhr.send();
            
            if (xhr.status === 200) {
              // Succès - parser la réponse
              try {
                var responseData = JSON.parse(xhr.responseText);
                return JSON.stringify({
                  success: true,
                  data: responseData,
                  status: xhr.status,
                  platform: 'iOS_compatible'
                });
              } catch (parseError) {
                return JSON.stringify({
                  success: false,
                  error: 'Erreur parsing JSON: ' + parseError.message,
                  rawResponse: xhr.responseText.substring(0, 200),
                  status: xhr.status
                });
              }
            } else {
              // Erreur HTTP
              return JSON.stringify({
                success: false,
                status: xhr.status,
                error: 'Erreur HTTP ' + xhr.status,
                responseText: xhr.responseText.substring(0, 200),
                needsLogin: xhr.status === 401
              });
            }
            
          } catch (networkError) {
            return JSON.stringify({
              success: false,
              error: 'Erreur réseau: ' + networkError.message,
              networkError: true
            });
          }
          
        } catch (globalError) {
          return JSON.stringify({
            success: false,
            error: 'Erreur globale: ' + globalError.message,
            jsError: true
          });
        }
      })()
    ''');

      if (result != null && result.toString() != 'null') {
        await handleApiResponseFixed(result.toString());
      } else {
        print('❌ Pas de résultat de l\'API');
        // Ne pas faire de fallback sur URL - c'est le problème !
        print('🔄 Aucune extraction URL - attendre que l\'API fonctionne');
      }
    } catch (e) {
      print('❌ Erreur récupération profil: $e');
      // NE PAS faire de fallback sur extractProfileFromUrl()
      print(
          '🚨 Erreur JavaScript détectée - Il faut corriger l\'API, pas utiliser l\'URL');
    }
  }

// MODIFIÉE : Nouvelle méthode pour traiter la réponse de l'API avec navigation
  Future<void> handleApiResponseFixed(String resultString) async {
    try {
      String cleanResult = resultString;

      // Nettoyage de la chaîne JSON
      if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
        cleanResult = cleanResult.substring(1, cleanResult.length - 1);
      }

      cleanResult = cleanResult.replaceAll('\\"', '"');
      cleanResult = cleanResult.replaceAll('\\\\', '\\');

      final response = json.decode(cleanResult);
      print('📡 Réponse API nettoyée: $response');

      if (response['success'] == true && response['data'] != null) {
        final apiData = response['data'];
        print('📋 Données API reçues: $apiData');

        // Vérifier si on a les données utilisateur directement
        if (apiData['success'] == true && apiData['data'] != null) {
          final profileData = apiData['data'];
          print('👤 Données profil: $profileData');

          setState(() {
            userProfile = UserProfile.fromJson(profileData);
          });

          print(
              '✅ PROFIL API RÉCUPÉRÉ: ${userProfile.firstName} (ID: ${userProfile.id})');

          // NOUVEAU : Navigation automatique après récupération du profil
          await checkAndNavigateToDashboard();
        } else {
          print('❌ Format de données API inattendu: $apiData');
          await handleApiErrorFixed(apiData);
        }
      } else {
        print('❌ Échec de l\'API: $response');
        await handleApiErrorFixed(response);
      }
    } catch (parseError) {
      print('❌ Erreur parsing API: $parseError');
      print('📜 Données brutes: ${resultString.substring(0, 200)}...');
    }
  }

// Gestion d'erreur sans fallback URL
  Future<void> handleApiErrorFixed(Map<String, dynamic> response) async {
    final status = response['status'];

    print('🚨 Erreur API - Status: $status');
    print('🚨 Détails erreur: ${response['error']}');

    if (status == 401 || response['needsLogin'] == true) {
      print('🔒 Non authentifié - redirection vers login recommandée');
      setState(() {
        userProfile = UserProfile.notAuthenticated();
      });
      await suggestLogin();
    } else if (response['needsRefresh'] == true) {
      print('🔄 Page doit être rafraîchie pour récupérer le token CSRF');
      await refreshPageAndRetry();
    } else if (response['networkError'] == true) {
      print('🌐 Erreur réseau - vérifier la connexion');
      setState(() {
        userProfile = UserProfile(
          firstName: 'Erreur réseau',
          loading: false,
          isAuthenticated: false,
        );
      });
    } else {
      print('❓ Erreur API inconnue: ${response['error']}');
      setState(() {
        userProfile = UserProfile(
          firstName: 'Erreur API',
          loading: false,
          isAuthenticated: false,
        );
      });
    }
  }

// Test pour vérifier si l'API fonctionne maintenant
  Future<void> testAPIConnection() async {
    try {
      print('🧪 Test de connexion API...');

      final testResult = await controller.runJavaScriptReturningResult('''
      (function() {
        try {
          // Test simple pour voir si XMLHttpRequest fonctionne
          var xhr = new XMLHttpRequest();
          xhr.open('GET', window.location.href, false);
          xhr.send();
          
          return JSON.stringify({
            test: 'success',
            status: xhr.status,
            hasCSRF: document.querySelector('meta[name="csrf-token"]') !== null,
            currentUrl: window.location.href,
            platform: navigator.userAgent.includes('iPhone') ? 'iOS' : 'other'
          });
        } catch (error) {
          return JSON.stringify({
            test: 'failed',
            error: error.message,
            platform: navigator.userAgent.includes('iPhone') ? 'iOS' : 'other'
          });
        }
      })()
    ''');

      if (testResult != null) {
        final test = json.decode(
            testResult.toString().replaceAll('"', '').replaceAll('\\"', '"'));
        print('🧪 Résultat test API: $test');

        if (test['test'] == 'success') {
          print('✅ XMLHttpRequest fonctionne sur cette plateforme');
          print('🔐 Token CSRF disponible: ${test['hasCSRF']}');
          print('📱 Plateforme: ${test['platform']}');
        } else {
          print('❌ XMLHttpRequest ne fonctionne pas: ${test['error']}');
        }
      }
    } catch (e) {
      print('❌ Erreur test API: $e');
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

            print(
                '✅ PROFIL CRÉÉ: ${userProfile.firstName} (ID: ${userProfile.id})');

            // NOUVEAU : Navigation automatique après extraction URL aussi
            await checkAndNavigateToDashboard();
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

          print(
              '✅ PROFIL RÉCUPÉRÉ VIA API: ${userProfile.firstName} (ID: ${userProfile.id})');

          // NOUVEAU : Navigation automatique après récupération du profil
          await checkAndNavigateToDashboard();
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
          content: const Text(
              '🔒 Vous devez vous connecter pour accéder à votre profil'),
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

  // MODIFIÉE : Méthode d'envoi de notification de bienvenue avec gestion iOS
  Future<void> sendWelcomeNotification() async {
    if (userProfile.id == null) {
      print('⚠️ Pas d\'utilisateur pour notification');
      return;
    }

    try {
      print('📱 Envoi notification système de bienvenue...');

      // Vérifier et demander les permissions si nécessaire
      if (!notificationsInitialized) {
        if (Platform.isIOS) {
          print('🍎 [iOS] Demande de permissions notifications...');
          final bool granted = await NotificationService.requestPermissions();

          setState(() {
            notificationsInitialized = granted;
          });

          if (!granted) {
            print('❌ [iOS] Permissions refusées');
            if (mounted) {
              _showNotificationPermissionDialog();
            }
            return;
          }
        } else {
          print('🤖 [Android] Notifications non autorisées');
          return;
        }
      }

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
            content: Text(
                '📱 Bienvenue ${userProfile.firstName} ! Vous êtes maintenant sur le dashboard ✅'),
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

      if (Platform.isIOS) {
        // Demander les permissions iOS
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
            content: Text(
                '📱 [${Platform.isIOS ? "iOS" : "Android"}] Notification de test envoyée !'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
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

      print(
          '✅ Notifications programmées avec succès (incluant rappels automatiques)');
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
                Text(
                    'Reprogrammation: ${status['has_reprogramming'] ? "✅" : "❌"}'),
                if (status['next_reminder'] != null)
                  Text('Prochain: ${status['next_reminder']}'),
                if (status['error'] != null)
                  Text('Erreur: ${status['error']}',
                      style: const TextStyle(color: Colors.red)),
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
                  if (userProfile.id != null &&
                      upcomingEvaluations.isNotEmpty) {
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
      body: SafeArea(
        child: Stack(
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
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 50),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
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

            // NOUVEAU : Bouton de navigation dashboard (temporaire pour debug)
            if (userProfile.id != null &&
                userProfile.firstName != 'Utilisateur' &&
                userProfile.firstName != 'Non connecté')
              Positioned(
                top: 60,
                right: 20,
                child: FloatingActionButton.extended(
                  heroTag: "dashboard_nav",
                  onPressed: () async {
                    print('🎯 Navigation manuelle vers dashboard...');
                    // CORRECTION : Format correct
                    final dashboardUrl =
                        'https://ouibuddy.com/${userProfile.id}/dashboard';
                    print('🚀 URL: $dashboardUrl');

                    await controller.loadRequest(Uri.parse(dashboardUrl));

                    // Vérifier après 3 secondes
                    Future.delayed(const Duration(seconds: 3), () async {
                      final currentUrl = await controller
                          .runJavaScriptReturningResult('window.location.href');
                      print(
                          '📍 Nouvelle URL: ${currentUrl?.toString().replaceAll('"', '')}');
                    });
                  },
                  backgroundColor: Colors.green,
                  icon: const Icon(Icons.dashboard, color: Colors.white),
                  label: Text(
                    'Dashboard\n${userProfile.firstName}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),

            // Floating Action Button pour les évaluations
            if (showEvaluations && upcomingEvaluations.isNotEmpty)
              Positioned(
                bottom: 100,
                right: 20,
                child: FloatingActionButton.extended(
                  heroTag: "evaluations",
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
            if (showEvaluations &&
                upcomingEvaluations.any((e) => e.isToday || e.isTomorrow))
              Positioned(
                bottom: 160,
                right: 20,
                child: FloatingActionButton(
                  heroTag: "urgent_notifications",
                  onPressed: () async {
                    await notifyUrgentEvaluations();
                  },
                  backgroundColor: Colors.red,
                  child: const Icon(Icons.notification_important,
                      color: Colors.white),
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
                          'ID: ${userProfile.id} • Auth: ${userProfile.isAuthenticated ? "✅" : "❌"} • ${Platform.isIOS ? "🍎 iOS" : "🤖 Android"}',
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
                          if (upcomingEvaluations
                              .any((e) => e.isToday || e.isTomorrow))
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
                        Text(
                          '${Platform.isIOS ? "🍎 iOS" : "🤖 Android"}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
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
            // NOUVEAU : Barre de boutons en bas
            Positioned(
              bottom: 100, // Au-dessus du widget profil
              left: 20,
              right: 80, // Laisser de la place pour les FAB à droite
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade100.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Bouton actualiser
                    IconButton(
                      icon: Icon(
                        Icons.refresh,
                        color: isCheckingAuth ? Colors.orange : Colors.blue,
                      ),
                      onPressed: isCheckingAuth ? null : forceProfileCheck,
                      tooltip: 'Actualiser profil',
                    ),

                    // Bouton évaluations
                    if (userProfile.id != null)
                      IconButton(
                        icon: Stack(
                          children: [
                            Icon(
                              Icons.assignment,
                              color:
                                  showEvaluations ? Colors.green : Colors.blue,
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
                        tooltip: showEvaluations
                            ? 'Voir évaluations'
                            : 'Charger évaluations',
                      ),

                    // Bouton notifications
                    IconButton(
                      icon: Icon(
                        Icons.notifications,
                        color: notificationsInitialized
                            ? Colors.green
                            : Colors.red,
                      ),
                      onPressed: () async {
                        if (notificationsInitialized) {
                          await testNotifications();
                        } else {
                          if (Platform.isIOS) {
                            // Demander les permissions iOS
                            final bool granted =
                                await NotificationService.requestPermissions();
                            setState(() {
                              notificationsInitialized = granted;
                            });

                            if (granted) {
                              await testNotifications();
                            } else {
                              _showNotificationPermissionDialog();
                            }
                          } else {
                            _showNotificationPermissionDialog();
                          }
                        }
                      },
                      tooltip: notificationsInitialized
                          ? 'Test notifications'
                          : 'Activer notifications',
                    ),

                    // Bouton profil utilisateur
                    if (userProfile.id != null)
                      IconButton(
                        icon: const Icon(Icons.person, color: Colors.blue),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text(
                                  '👤 Profil Utilisateur ${Platform.isIOS ? "🍎" : "🤖"}'),
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
                                  Text(
                                      'Plateforme: ${Platform.isIOS ? "iOS" : "Android"}'),
                                  Text(
                                      'Session: ${sessionToken != null ? "✅ Active" : "❌ Inactive"}'),
                                  Text(
                                      'Authentifié: ${userProfile.isAuthenticated ? "✅ Oui" : "❌ Non"}'),
                                  Text(
                                      'Notifications: ${notificationsInitialized ? "✅ Actives" : "❌ Inactives"}'),
                                  Text(
                                      'Évaluations: ${upcomingEvaluations.length} à venir'),
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

                    // Bouton menu plus (pour les autres fonctions)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, color: Colors.blue),
                      onSelected: (value) async {
                        switch (value) {
                          case 'rappels':
                            _showReminderStatus();
                            break;
                          case 'test_complet':
                            if (notificationsInitialized &&
                                userProfile.id != null) {
                              await NotificationService.runFullTest(
                                  userProfile.firstName, userProfile.id!);
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        '🧪 Test complet lancé sur ${Platform.isIOS ? "iOS" : "Android"} ! Vérifiez vos notifications'),
                                    backgroundColor: Colors.purple,
                                  ),
                                );
                              }
                            }
                            break;
                          case 'notifier_urgentes':
                            await notifyUrgentEvaluations();
                            break;
                          case 'force_dashboard':
                            if (userProfile.id != null) {
                              final dashboardUrl =
                                  'https://ouibuddy.com/${userProfile.id}/dashboard';
                              await controller
                                  .loadRequest(Uri.parse(dashboardUrl));
                            }
                            break;
                        }
                      },
                      itemBuilder: (context) => [
                        if (userProfile.id != null)
                          const PopupMenuItem(
                            value: 'rappels',
                            child: Row(
                              children: [
                                Icon(Icons.autorenew, color: Colors.teal),
                                SizedBox(width: 8),
                                Text('Rappels automatiques'),
                              ],
                            ),
                          ),
                        if (userProfile.id != null)
                          const PopupMenuItem(
                            value: 'test_complet',
                            child: Row(
                              children: [
                                Icon(Icons.science, color: Colors.purple),
                                SizedBox(width: 8),
                                Text('Test complet'),
                              ],
                            ),
                          ),
                        if (userProfile.id != null &&
                            upcomingEvaluations.isNotEmpty)
                          const PopupMenuItem(
                            value: 'notifier_urgentes',
                            child: Row(
                              children: [
                                Icon(Icons.notification_important,
                                    color: Colors.red),
                                SizedBox(width: 8),
                                Text('Notifier urgentes'),
                              ],
                            ),
                          ),
                        if (userProfile.id != null)
                          const PopupMenuItem(
                            value: 'force_dashboard',
                            child: Row(
                              children: [
                                Icon(Icons.dashboard, color: Colors.green),
                                SizedBox(width: 8),
                                Text('Forcer Dashboard'),
                              ],
                            ),
                          ),
                      ],
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

  // MODIFIÉE : Récupération des évaluations avec programmation automatique (compatible iOS/Android)
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

      // Version XMLHttpRequest synchrone pour iOS
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
          cleanDebugInfo =
              cleanDebugInfo.substring(1, cleanDebugInfo.length - 1);
        }
        cleanDebugInfo = cleanDebugInfo.replaceAll('\\"', '"');

        final debug = json.decode(cleanDebugInfo);
        print('🔍 [${Platform.isIOS ? "iOS" : "Android"}] Debug info: $debug');

        if ((debug['status'] == 'success' ||
                debug['status'] == 'ios_success') &&
            debug['hasData'] == true) {
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
              if (evaluations.isNotEmpty &&
                  userProfile.id != null &&
                  notificationsInitialized) {
                await BackgroundNotificationService.scheduleFromEvaluations(
                  userProfile.firstName,
                  userProfile.id!,
                  evaluations,
                );
                print(
                    '🔄 Rappels automatiques mis à jour avec ${evaluations.length} évaluations');
              }

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        '✅ [${Platform.isIOS ? "iOS" : "Android"}] ${evaluations.length} évaluations trouvées !'),
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
          String errorMsg = debug['error']?.toString() ??
              'Erreur de récupération des données';
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
      final urgentEvaluations = upcomingEvaluations
          .where(
              (eval) => eval.isToday || eval.isTomorrow || eval.daysUntil <= 2)
          .toList();

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
        final tomorrowCount =
            urgentEvaluations.where((e) => e.isTomorrow).length;
        final soonCount =
            urgentEvaluations.where((e) => !e.isToday && !e.isTomorrow).length;

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
            content: Text(
                '📱 [${Platform.isIOS ? "iOS" : "Android"}] ${urgentEvaluations.length} notifications envoyées pour les évaluations urgentes'),
            backgroundColor: urgentEvaluations.any((e) => e.isToday)
                ? Colors.red
                : Colors.orange,
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
