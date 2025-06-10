import 'package:flutter/material.dart';
import 'evaluation_service.dart';

// Widget pour afficher une évaluation individuelle
class EvaluationCard extends StatelessWidget {
  final Evaluation evaluation;
  final VoidCallback? onTap;

  const EvaluationCard({
    super.key,
    required this.evaluation,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête avec date et urgence
              Row(
                children: [
                  Icon(
                    _getUrgencyIcon(),
                    color: _getUrgencyColor(),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      evaluation.evaluationDateFormatted,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _getUrgencyColor(),
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getUrgencyColor().withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      evaluation.urgencyText,
                      style: TextStyle(
                        color: _getUrgencyColor(),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Matière et chapitre
              if (evaluation.topicCategory != null) ...[
                Row(
                  children: [
                    Icon(Icons.subject, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        evaluation.topicCategory!.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],

              // Description
              if (evaluation.description != null && evaluation.description!.isNotEmpty) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.description, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        evaluation.description!,
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 13,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
              ],

              // Informations supplémentaires
              Row(
                children: [
                  if (evaluation.fromPronote) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Pronote',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  if (evaluation.fromSchoolhub) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'SchoolHub',
                        style: TextStyle(
                          color: Colors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],

                  if (evaluation.isPartOfGroup) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Groupe (${evaluation.groupMembersCount})',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],

                  const Spacer(),

                  Text(
                    evaluation.evaluationDayName,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getUrgencyIcon() {
    switch (evaluation.urgencyLevel) {
      case 'critical':
        return Icons.warning;
      case 'high':
        return Icons.schedule;
      case 'medium':
        return Icons.access_time;
      case 'low':
        return Icons.event;
      default:
        return Icons.event_note;
    }
  }

  Color _getUrgencyColor() {
    switch (evaluation.urgencyLevel) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.amber;
      case 'low':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}

// Widget pour afficher le résumé des évaluations
class EvaluationSummaryWidget extends StatelessWidget {
  final EvaluationSummary summary;

  const EvaluationSummaryWidget({
    super.key,
    required this.summary,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Résumé des évaluations',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Statistiques en grille
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              childAspectRatio: 2.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 8,
              children: [
                _buildStatCard(
                  'Total',
                  summary.totalEvaluations.toString(),
                  Icons.assignment,
                  Colors.blue,
                ),
                _buildStatCard(
                  'Aujourd\'hui',
                  summary.todayCount.toString(),
                  Icons.today,
                  Colors.red,
                ),
                _buildStatCard(
                  'Demain',
                  summary.tomorrowCount.toString(),
                  Icons.add,
                  Colors.orange,
                ),
                _buildStatCard(
                  'Cette semaine',
                  summary.thisWeekCount.toString(),
                  Icons.date_range,
                  Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 6),
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Widget principal pour la liste des évaluations
class EvaluationsList extends StatelessWidget {
  final List<Evaluation> evaluations;
  final EvaluationSummary? summary;
  final bool isLoading;
  final String? errorMessage;
  final VoidCallback? onRefresh;

  const EvaluationsList({
    super.key,
    required this.evaluations,
    this.summary,
    this.isLoading = false,
    this.errorMessage,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Chargement des évaluations...'),
          ],
        ),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            if (onRefresh != null)
              ElevatedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
          ],
        ),
      );
    }

    if (evaluations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.event_available, size: 64, color: Colors.green),
            SizedBox(height: 16),
            Text(
              'Aucune évaluation à venir !',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Profitez de cette période sans évaluations 😊',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (onRefresh != null) {
          onRefresh!();
        }
      },
      child: CustomScrollView(
        slivers: [
          // Résumé
          if (summary != null)
            SliverToBoxAdapter(
              child: EvaluationSummaryWidget(summary: summary!),
            ),

          // En-tête de liste
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.event_note, color: Colors.blue),
                  const SizedBox(width: 8),
                  Text(
                    'Évaluations à venir (${evaluations.length})',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Liste des évaluations
          SliverList(
            delegate: SliverChildBuilderDelegate(
                  (context, index) {
                final evaluation = evaluations[index];
                return EvaluationCard(
                  evaluation: evaluation,
                  onTap: () {
                    _showEvaluationDetails(context, evaluation);
                  },
                );
              },
              childCount: evaluations.length,
            ),
          ),

          // Espacement en bas
          const SliverToBoxAdapter(
            child: SizedBox(height: 80),
          ),
        ],
      ),
    );
  }

  void _showEvaluationDetails(BuildContext context, Evaluation evaluation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('📚 ${evaluation.topicCategory?.name ?? 'Évaluation'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow('📅 Date', evaluation.evaluationDateFormatted),
            _buildDetailRow('⏰ Dans', evaluation.urgencyText),
            if (evaluation.description != null)
              _buildDetailRow('📝 Description', evaluation.description!),
            if (evaluation.chapter != null)
              _buildDetailRow('📖 Chapitre', evaluation.chapter!.name),
            if (evaluation.isPartOfGroup)
              _buildDetailRow('👥 Groupe', '${evaluation.groupMembersCount} évaluations'),
            _buildDetailRow('📱 Source',
                evaluation.fromPronote ? 'Pronote' :
                evaluation.fromSchoolhub ? 'SchoolHub' : 'Manuel'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
          ),
        ],
      ),
    );
  }
}