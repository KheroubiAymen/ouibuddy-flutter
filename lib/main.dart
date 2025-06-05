import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'notification_service.dart'; // NOUVEAU IMPORT

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NOUVEAU : Initialiser les notifications avant runApp
  await NotificationService.initialize();

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

// SUPPRIMÉ : L'ancienne classe NotificationService
// Elle est maintenant dans notification_service.dart

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

class _WebViewPageState extends State<WebViewPage> {
  late final WebViewController controller;
  bool isLoading = true;
  bool hasError = false;
  int retryCount = 0;
  String? sessionToken;
  UserProfile userProfile = UserProfile.loading();
  bool notificationsInitialized = false;
  bool isCheckingAuth = false;

  @override
  void initState() {
    super.initState();
    initializeNotifications();
    initController();
  }

  // NOUVELLE méthode d'initialisation des notifications
  Future<void> initializeNotifications() async {
    try {
      // Vérifier si les notifications sont autorisées
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

  // NOUVELLE méthode pour demander l'autorisation des notifications
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
        // Surveiller les changements d'URL
        let lastUrl = window.location.href;
        
        setInterval(function() {
          if (window.location.href !== lastUrl) {
            lastUrl = window.location.href;
            console.log('🔄 URL changée:', lastUrl);
            
            // Si on arrive sur le dashboard, essayer d'extraire le profil
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

  // Méthode principale corrigée pour extraire session et profil
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

  // Méthode corrigée pour extraire les informations de session Laravel
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
            
            // Extraire les cookies Laravel spécifiques
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
            
            // Récupérer le token CSRF depuis les meta tags
            const csrfMeta = document.querySelector('meta[name="csrf-token"]');
            if (csrfMeta) {
              sessionInfo.csrf_token = csrfMeta.getAttribute('content');
            }
            
            // Vérifier si on a les éléments d'une session active
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
        // Méthode de parsing robuste
        String cleanResult = result.toString();

        if (cleanResult.startsWith('"') && cleanResult.endsWith('"')) {
          cleanResult = cleanResult.substring(1, cleanResult.length - 1);
        }

        cleanResult = cleanResult.replaceAll('\\"', '"');
        cleanResult = cleanResult.replaceAll('\\\\', '\\');

        print('🔍 Session data (cleaned): $cleanResult');

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

        print('🍪 Cookies bruts: $cookieString');
        print('🔒 CSRF Token: $csrfString');

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

  // Méthode corrigée pour vérifier l'authentification
  Future<bool> checkAuthenticationStatus() async {
    try {
      print('🔍 Vérification du statut d\'authentification...');

      final result = await controller.runJavaScriptReturningResult('''
        (function() {
          try {
            const checks = {
              currentUrl: window.location.href,
              
              // Vérifier les cookies Laravel spécifiques
              hasLaravelSession: document.cookie.includes('laravel_session'),
              hasXSRFToken: document.cookie.includes('XSRF-TOKEN'),
              
              // Vérifier le token CSRF dans les meta tags
              hasCSRFToken: document.querySelector('meta[name="csrf-token"]') !== null,
              
              // Vérifier les éléments UI d'utilisateur connecté
              hasUserElements: document.querySelector('.user-info, .profile-info, [data-user], .logout-btn, .dashboard, .user-dropdown') !== null,
              
              // Vérifier si on est sur une page qui nécessite une authentification
              isOnPrivatePage: window.location.href.includes('/dashboard') ||
                              window.location.href.includes('/profile') ||
                              window.location.href.includes('/admin') ||
                              window.location.href.includes('/user'),
              
              // Vérifier si on est sur la page de login
              isOnLoginPage: window.location.href.includes('/login') ||
                            window.location.href.includes('/auth') ||
                            document.querySelector('form[action*="login"], input[name="email"][type="email"]') !== null,
              
              // Compter les cookies pour diagnostic
              cookiesCount: document.cookie.split(';').filter(c => c.trim()).length,
              
              // Vérifier si on a un ID utilisateur dans l'URL
              hasUserIdInUrl: /\\/\\d+\\//.test(window.location.pathname)
            };
            
            // Logique d'authentification plus permissive
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

        print('🔍 Auth status (cleaned): $cleanResult');

        final authStatus = json.decode(cleanResult);
        print('🔍 Statut authentification parsé: $authStatus');
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

        print('🌐 URL simple: $urlString');
        print('📍 Path simple: $pathString');

        bool onDashboard = urlString.contains('/dashboard');
        bool hasIdInPath = RegExp(r'/\d+/').hasMatch(pathString);
        bool notOnLogin = !urlString.contains('/login');

        bool isAuth = onDashboard && hasIdInPath && notOnLogin;

        print('🔍 Auth simple - Dashboard: $onDashboard, ID: $hasIdInPath, NotLogin: $notOnLogin = $isAuth');

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
            console.log('🚀 Début appel API profile...');
            
            const csrfToken = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content');
            
            if (!csrfToken) {
              console.warn('⚠️ Pas de token CSRF trouvé');
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
            
            console.log('📡 Status:', response.status);
            
            if (response.ok) {
              const data = await response.json();
              console.log('✅ Données reçues:', data);
              return JSON.stringify({
                success: true,
                data: data,
                status: response.status
              });
            } else {
              const errorText = await response.text();
              console.error('❌ Erreur HTTP:', response.status, errorText);
              return JSON.stringify({
                success: false,
                status: response.status,
                error: errorText,
                needsLogin: response.status === 401
              });
            }
          } catch (error) {
            console.error('❌ Erreur fetch:', error);
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

  // Extraire le profil depuis l'URL (méthode améliorée)
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
          
          // Extraire l'ID depuis l'URL comme /62/dashboard
          const urlMatch = window.location.pathname.match(/\\/(\\d+)\\//);
          if (urlMatch) {
            profile.id = parseInt(urlMatch[1]);
            console.log('📍 ID trouvé dans URL:', profile.id);
          }
          
          // Essayer de trouver le nom dans le contenu de la page
          const textContent = document.body.innerText || document.body.textContent || '';
          
          // Patterns améliorés pour trouver le prénom
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
              console.log('📝 Prénom trouvé avec pattern:', profile.first_name);
              break;
            }
          }
          
          // Chercher dans les éléments avec des classes/id spécifiques
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
                console.log('🏷️ Prénom trouvé dans élément:', profile.first_name);
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
      print('📋 Réponse API: $response');

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
      print('❌ Données: $resultString');
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

  // NOUVELLE méthode d'envoi de notification de bienvenue
  Future<void> sendWelcomeNotification() async {
    if (!notificationsInitialized || userProfile.id == null) {
      print('⚠️ Notifications non autorisées ou pas d\'utilisateur');
      return;
    }

    try {
      print('📱 Envoi notification système de bienvenue...');

      // Envoyer la notification système
      await NotificationService.showWelcomeNotification(
        userProfile.firstName,
        userProfile.id!,
      );

      // Afficher aussi un SnackBar dans l'app
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📱 Notification envoyée à ${userProfile.firstName} !'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Test',
              onPressed: () => testNotifications(),
            ),
          ),
        );
      }

      print('✅ Notification système envoyée avec succès');

    } catch (e) {
      print('❌ Erreur envoi notification: $e');
    }
  }

  // NOUVELLE méthode de test des notifications
  Future<void> testNotifications() async {
    if (!notificationsInitialized) {
      print('❌ Notifications non autorisées');
      _showNotificationPermissionDialog();
      return;
    }

    try {
      // Test notification simple
      await NotificationService.showTestNotification(userProfile.firstName);

      print('✅ Notification de test envoyée');

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
          // NOUVEAU bouton notifications amélioré
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
          // NOUVEAU bouton pour test complet
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
                      ],
                    ),
                    actions: [
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
}