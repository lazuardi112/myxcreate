import 'package:flutter/material.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final IconData icon;
  final List<Widget>? actions;

  const CustomAppBar({
    super.key,
    required this.title,
    required this.icon,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(90);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
      child: Container(
        height: preferredSize.height,
        color: Colors.deepPurple,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SafeArea(
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.white.withOpacity(0.15),
                child: Icon(icon, size: 26, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (actions != null) ...actions!,
            ],
          ),
        ),
      ),
    );
  }
}

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 75,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: BottomNavigationBar(
              currentIndex: currentIndex,
              onTap: onTap,
              selectedItemColor: Colors.deepPurple,
              unselectedItemColor: Colors.grey,
              showUnselectedLabels: true,
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.person),
                  label: "Profil",
                ),
                BottomNavigationBarItem(
                  icon: SizedBox.shrink(),
                  label: "",
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.settings),
                  label: "Pengaturan",
                ),
              ],
            ),
          ),
          Positioned(
            bottom: 10,
            child: GestureDetector(
              onTap: () => onTap(1),
              child: Container(
                width: 65,
                height: 65,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.deepPurple,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black26,
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    )
                  ],
                ),
                child: const Icon(Icons.dashboard_customize, color: Colors.white, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
