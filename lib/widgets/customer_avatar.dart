import 'package:flutter/material.dart';

import '../models/app_data.dart';

const customerAvatarAssets = <String>[
  'assets/images/avatars/customer_dog_1.png',
  'assets/images/avatars/customer_dog_2.png',
  'assets/images/avatars/customer_dog_3.png',
  'assets/images/avatars/customer_dog_4.png',
];

class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({super.key, required this.customer, required this.size});

  final Customer customer;
  final double size;

  @override
  Widget build(BuildContext context) {
    final index =
        customer.avatarIndex >= 0 &&
            customer.avatarIndex < customerAvatarAssets.length
        ? customer.avatarIndex
        : customer.id.codeUnits.fold<int>(0, (sum, unit) => sum + unit) %
              customerAvatarAssets.length;
    return Semantics(
      label: 'Avatar de ${customer.name}',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        padding: EdgeInsets.all(size * .07),
        child: Image.asset(
          customerAvatarAssets[index],
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}
