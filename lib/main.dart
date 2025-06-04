import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
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
  String? authToken;

  @override
  void initState() {
    super.initState();
    initController();
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
            // Récupérer le token après le chargement de la page
            extractToken();
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
    });
    controller.reload();
  }

  // Méthode pour extraire le token depuis la WebView
  Future<void> extractToken() async {
    try {
      // Méthode 1: Récupérer depuis localStorage
      final localStorageToken = await controller.runJavaScriptReturningResult(
          "localStorage.getItem('auth_token') || localStorage.getItem('token') || localStorage.getItem('access_token')"
      );

      if (localStorageToken != null && localStorageToken.toString() != 'null') {
        authToken = localStorageToken.toString().replaceAll('"', '');
        print('🔑 TOKEN TROUVÉ dans localStorage: $authToken');
        setState(() {});
        return;
      }

      // Méthode 2: Récupérer depuis sessionStorage
      final sessionStorageToken = await controller.runJavaScriptReturningResult(
          "sessionStorage.getItem('auth_token') || sessionStorage.getItem('token') || sessionStorage.getItem('access_token')"
      );

      if (sessionStorageToken != null && sessionStorageToken.toString() != 'null') {
        authToken = sessionStorageToken.toString().replaceAll('"', '');
        print('🔑 TOKEN TROUVÉ dans sessionStorage: $authToken');
        setState(() {});
        return;
      }

      // Méthode 3: Récupérer depuis les cookies
      final cookies = await controller.runJavaScriptReturningResult(
          "document.cookie"
      );

      if (cookies != null && cookies.toString().isNotEmpty) {
        print('🍪 COOKIES: $cookies');
        // Parser les cookies pour trouver le token
        final cookieString = cookies.toString();
        final tokenFromCookie = extractTokenFromCookies(cookieString);
        if (tokenFromCookie != null) {
          authToken = tokenFromCookie;
          print('🔑 TOKEN TROUVÉ dans cookies: $authToken');
          setState(() {});
          return;
        }
      }

      // Méthode 4: Vérifier si un élément contient le token (pour débugger)
      final debugInfo = await controller.runJavaScriptReturningResult('''
        (function() {
          var info = {
            url: window.location.href,
            title: document.title,
            localStorage_keys: Object.keys(localStorage),
            sessionStorage_keys: Object.keys(sessionStorage),
            cookies: document.cookie,
            hasAuthForm: !!document.querySelector('[name="email"], [name="password"], .login-form, .auth-form')
          };
          return JSON.stringify(info);
        })()
      ''');

      print('🔍 DEBUG INFO: $debugInfo');

    } catch (e) {
      print('❌ Erreur lors de l\'extraction du token: $e');
    }
  }

  // Extraire le token depuis les cookies
  String? extractTokenFromCookies(String cookieString) {
    final cookies = cookieString.split(';');
    for (final cookie in cookies) {
      final parts = cookie.trim().split('=');
      if (parts.length == 2) {
        final key = parts[0].trim();
        final value = parts[1].trim();

        // Chercher différents noms de token possibles
        if (key.toLowerCase().contains('token') ||
            key.toLowerCase().contains('auth') ||
            key.toLowerCase().contains('access') ||
            key == 'laravel_session') {
          return value;
        }
      }
    }
    return null;
  }

  // Méthode pour tester l'API avec le token
  Future<void> testApiWithToken() async {
    if (authToken == null) {
      print('❌ Aucun token disponible pour tester l\'API');
      return;
    }

    try {
      // Injecter du code JavaScript pour faire un appel API
      await controller.runJavaScript('''
        fetch('https://ouibuddy.com/api/user', {
          method: 'GET',
          headers: {
            'Authorization': 'Bearer $authToken',
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          }
        })
        .then(response => response.json())
        .then(data => {
          console.log('API Response:', data);
          alert('API Response: ' + JSON.stringify(data));
        })
        .catch(error => {
          console.error('API Error:', error);
          alert('API Error: ' + error.message);
        });
      ''');
    } catch (e) {
      print('❌ Erreur lors du test API: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('OuiBuddy'),
        actions: [
          if (authToken != null)
            IconButton(
              icon: const Icon(Icons.api),
              onPressed: testApiWithToken,
              tooltip: 'Tester API',
            ),
          IconButton(
            icon: const Icon(Icons.token),
            onPressed: extractToken,
            tooltip: 'Récupérer Token',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: reloadPage,
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
                  const SizedBox(height: 10),
                  const Text('ERR_CACHE_MISS'),
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
          // Afficher le token en bas de l'écran s'il existe
          if (authToken != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '🔑 Token récupéré:',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      authToken!.length > 50
                          ? '${authToken!.substring(0, 50)}...'
                          : authToken!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}