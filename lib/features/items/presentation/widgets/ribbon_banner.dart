import 'package:flutter/material.dart';

enum RibbonType { featured, boosted, newArrival, popular, topRated }

class RibbonBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const RibbonBanner({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  factory RibbonBanner.fromType(RibbonType type) {
    switch (type) {
      case RibbonType.featured:
        return const RibbonBanner(
          text: 'FEATURED',
          color: Color(0xFFFF9800),
          icon: Icons.star_rounded,
        );
      case RibbonType.boosted:
        return const RibbonBanner(
          text: 'BOOSTED',
          color: Color(0xFF7B40B5),
          icon: Icons.bolt_rounded,
        );
      case RibbonType.newArrival:
        return const RibbonBanner(
          text: 'NEW',
          color: Color(0xFF00C853),
          icon: Icons.new_releases_rounded,
        );
      case RibbonType.popular:
        return const RibbonBanner(
          text: 'POPULAR',
          color: Color(0xFFFF5252),
          icon: Icons.local_fire_department_rounded,
        );
      case RibbonType.topRated:
        return const RibbonBanner(
          text: 'TOP RATED',
          color: Color(0xFF0288D1),
          icon: Icons.verified_rounded,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 12),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
