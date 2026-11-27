import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class AboutAppScreen extends StatelessWidget {
  const AboutAppScreen({super.key});

  static const _primaryOrange = Color(0xFFFF6B00);
  static const _lightOrange = Color(0xFFFFF7ED);
  static const _borderOrange = Color(0xFFFFE0CC);

  @override
  Widget build(BuildContext context) {
    AppLanguage.watch(context);
    final lang = Localizations.localeOf(context).languageCode;
    final isZh = lang == 'zh';
    final isMs = lang == 'ms';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _primaryOrange,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          isZh
              ? '关于本地生活服务助手'
              : (isMs
              ? 'Mengenai Pembantu Perkhidmatan Kehidupan Tempatan'
              : 'About Local Life Service Assistant'),
          // 👇 强制指定白色，并防止长标题溢出
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 16,
            color: Colors.white, // 强制白色
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        children: [
          // Welcome Banner Card
          Card(
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: _borderOrange),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _lightOrange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.work_outline,
                      color: _primaryOrange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isZh
                        ? '欢迎使用本地生活服务助手'
                        : (isMs
                        ? 'Selamat Datang ke Pembantu Perkhidmatan Kehidupan Tempatan'
                        : 'Welcome to Local Life Service Assistant'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF111827),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isZh
                        ? '轻松发展您的服务业务、管理预约并与本地客户建立联系。'
                        : (isMs
                        ? 'Kembangkan perniagaan perkhidmatan anda, urus tempahan, dan berhubung dengan pelanggan tempatan dengan mudah.'
                        : 'Grow your service business, manage bookings, and connect with local customers effortlessly.'),
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Colors.grey.shade600,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          _buildInfoCard(
            title: isZh
                ? '您的业务，精简高效'
                : (isMs ? 'Perniagaan anda, diperkemas' : 'Your business, streamlined'),
            content: isZh
                ? '本地生活服务助手将服务列表、智能职位匹配、客户消息和日程管理整合到一个工作区中。展示您的服务、上传证书以建立信任、设置您的覆盖半径和工作时间，并跟踪您的评分。'
                : (isMs
                ? 'Pembantu Perkhidmatan Kehidupan Tempatan menggabungkan senarai perkhidmatan, padanan pekerjaan pintar, pemesejan pelanggan dan pengurusan jadual ke dalam satu ruang kerja. Pamerkan perkhidmatan anda, muat naik sijil untuk membina kepercayaan, tetapkan radius liputan dan waktu bekerja anda, dan jejaki penilaian anda.'
                : 'Local Life Service Assistant brings service listings, smart job matching, customer messaging, and schedule management into one workspace. Showcase your services, upload certificates to build trust, set your coverage radius and working hours, and track your ratings.'),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: isZh
                ? '从职位匹配到付款'
                : (isMs ? 'Dari padanan pekerjaan ke pembayaran' : 'From job match to payout'),
            content: isZh
                ? '查看收到的预约请求，或通过 AI 职位匹配发现推荐的工作。一旦您接受请求并且客户完成付款，请在您工作时更新您的工作状态，并在完成后通过您的收益面板直接接收付款。'
                : (isMs
                ? 'Semak permintaan tempahan yang masuk atau temui pekerjaan yang disyorkan melalui Padanan Pekerjaan AI. Setelah anda menerima permintaan dan pelanggan melengkapkan pembayaran, kemas kini status kerja anda semasa anda bekerja dan terima pembayaran terus melalui Papan Pemuka Pendapatan anda selepas selesai.'
                : 'Review incoming booking requests or discover recommended jobs through AI Job Matching. Once you accept a request and the customer completes payment, update your job status as you work and receive payouts directly through your Earnings Dashboard after completion.'),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: isZh
                ? '沟通与支持'
                : (isMs ? 'Komunikasi dan sokongan' : 'Communication and support'),
            content: isZh
                ? '使用应用内聊天与客户确认服务要求、到达时间或特殊指示。保持您的个人资料经过验证且可用性为最新状态，以最大化预约机会并保持平稳运营。'
                : (isMs
                ? 'Gunakan Sembang dalam apl untuk mengesahkan keperluan perkhidmatan, masa ketibaan atau arahan khas dengan pelanggan. Pastikan profil anda disahkan dan ketersediaan dikemas kini untuk memaksimumkan peluang tempahan dan mengekalkan operasi yang lancar.'
                : 'Use in-app Chat to confirm service requirements, arrival times, or special instructions with customers. Keep your profile verified and availability up to date to maximize booking opportunities and maintain smooth operations.'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard({required String title, required String content}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _borderOrange),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              content,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}