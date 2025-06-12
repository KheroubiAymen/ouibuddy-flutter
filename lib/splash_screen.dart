import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<Offset> _slideAnimation;

  String _statusText = 'Initialisation...';
  bool _initializationComplete = false;

  @override
  void initState() {
    super.initState();

    // Configuration de la barre de statut
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
    );

    // Initialisation des animations
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 0.8, curve: Curves.elasticOut),
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.4, 1.0, curve: Curves.easeOutBack),
    ));

    // Démarrer l'animation
    _animationController.forward();

    // Initialisation de l'app
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      // Étape 1: Initialisation des services
      setState(() {
        _statusText = 'Initialisation des services...';
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // Étape 2: Préparation des notifications
      setState(() {
        _statusText = 'Configuration des notifications...';
      });
      await Future.delayed(const Duration(milliseconds: 600));

      // Étape 3: Connexion aux services
      setState(() {
        _statusText = 'Connexion aux services...';
      });
      await Future.delayed(const Duration(milliseconds: 800));

      // Étape 4: Finalisation
      setState(() {
        _statusText = 'Prêt !';
        _initializationComplete = true;
      });
      await Future.delayed(const Duration(milliseconds: 500));

      // Navigation vers l'écran principal
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }

    } catch (e) {
      setState(() {
        _statusText = 'Erreur d\'initialisation';
      });
      print('Erreur splash screen: $e');

      // En cas d'erreur, naviguer quand même après un délai
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E88E5), // Bleu principal
              Color(0xFF1565C0), // Bleu plus foncé
              Color(0xFF0D47A1), // Bleu très foncé
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Section principale avec logo et titre
              Expanded(
                flex: 3,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo animé
                      AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return FadeTransition(
                            opacity: _fadeAnimation,
                            child: ScaleTransition(
                              scale: _scaleAnimation,
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 20,
                                      offset: const Offset(0, 10),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.asset(
                                    'assets/images/logobuddy.png',
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.contain, // ou BoxFit.cover selon votre préférence
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 30),

                      // Titre animé
                      AnimatedBuilder(
                        animation: _animationController,
                        builder: (context, child) {
                          return SlideTransition(
                            position: _slideAnimation,
                            child: FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                children: [
                                  const Text(
                                    'OuiBuddy',
                                    style: TextStyle(
                                      fontSize: 48,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    height: 3,
                                    width: 100,
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  const Text(
                                    'Votre compagnon d\'études',
                                    style: TextStyle(
                                      fontSize: 18,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w300,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // Section du bas avec indicateur de chargement
              Expanded(
                flex: 1,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Indicateur de chargement animé
                    AnimatedBuilder(
                      animation: _animationController,
                      builder: (context, child) {
                        return FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            children: [
                              if (!_initializationComplete) ...[
                                const SizedBox(
                                  width: 30,
                                  height: 30,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                ),
                              ] else ...[
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              ],
                              const SizedBox(height: 20),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 300),
                                child: Text(
                                  _statusText,
                                  key: ValueKey(_statusText),
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w300,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 40),
                              // Icônes de fonctionnalités
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _buildFeatureIcon(Icons.notifications, 'Notifications'),
                                  _buildFeatureIcon(Icons.assignment, 'Évaluations'),
                                  _buildFeatureIcon(Icons.person, 'Profil'),
                                  _buildFeatureIcon(Icons.web, 'WebView'),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureIcon(IconData icon, String label) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 12,
            fontWeight: FontWeight.w300,
          ),
        ),
      ],
    );
  }
}