import 'package:flutter/material.dart';

class AccountGroup extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  const AccountGroup({super.key, this.title, required this.children});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
            child: Text(
              title!,
              style: const TextStyle(color: Colors.black54, fontSize: 13),
            ),
          ),
        Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                children[i],
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class AccountRow extends StatelessWidget {
  final String label;
  final String? value, subtitle;
  final IconData? icon;
  final VoidCallback? onTap;
  const AccountRow({
    super.key,
    required this.label,
    this.value,
    this.subtitle,
    this.icon,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    leading: icon == null ? null : Icon(icon),
    title: Text(label),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: value == null
        ? (onTap == null
              ? null
              : const Icon(Icons.chevron_right, color: Colors.grey))
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * .43,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.black54),
                  ),
                ),
                if (onTap != null)
                  const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
  );
}

String maskedEmail(String email) {
  final at = email.indexOf('@');
  return at > 0 ? '${email[0]}***${email.substring(at)}' : email;
}

String maskedPhone(String phone) =>
    phone.length > 4 ? '••••••${phone.substring(phone.length - 4)}' : phone;
