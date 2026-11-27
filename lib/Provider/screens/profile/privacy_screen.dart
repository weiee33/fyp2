import 'package:flutter/material.dart';
import 'package:fyp2/shared/localization/app_language.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

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
          isZh ? '隐私' : (isMs ? 'Privasi' : 'Privacy'),
          // 👇 在这里显式指定颜色为白色
          style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
      body: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card with Icon
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
                      Icons.shield_outlined,
                      color: _primaryOrange,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    isZh
                        ? '服务商数据与隐私'
                        : (isMs
                        ? 'Data dan privasi penyedia'
                        : 'Provider data and privacy'),
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
                        ? '本通知说明在本地生活服务助手中如何处理您的业务、验证和运营数据。'
                        : (isMs
                        ? 'Notis ini menerangkan cara data perniagaan, pengesahan dan operasi anda dikendalikan dalam Pembantu Perkhidmatan Kehidupan Tempatan.'
                        : 'This notice explains how your business, verification, and operational data are handled across Local Life Service Assistant.'),
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
                ? '业务资料与验证'
                : (isMs
                ? 'Profil perniagaan dan pengesahan'
                : 'Business profile and verification'),
            content: isZh
                ? '本地生活服务助手使用您的业务名称、联系方式、简介、服务列表、工作时间和覆盖区域向客户展示您的资料。上传的证书和身份证明文件将由授权管理员严格审核以进行账户验证。'
                : (isMs
                ? 'Pembantu Perkhidmatan Kehidupan Tempatan menggunakan nama perniagaan, butiran hubungan, bio, senarai perkhidmatan, waktu bekerja dan kawasan liputan anda untuk memaparkan profil anda kepada pelanggan. Sijil dan dokumen pengenalan yang dimuat naik disemak dengan ketat oleh pentadbir yang diberi kuasa untuk pengesahan akaun.'
                : 'Local Life Service Assistant uses your business name, contact details, bio, service listings, working hours, and coverage areas to display your profile to customers. Uploaded certifications and identification documents are reviewed strictly by authorised administrators for account verification.'),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: isZh
                ? '工作、位置与沟通'
                : (isMs
                ? 'Pekerjaan, lokasi dan komunikasi'
                : 'Jobs, location, and communication'),
            content: isZh
                ? '当您接受预约时，您将收到完成工作所需的客户服务地址和预约指示。您的服务区域半径和可用性用于支持 AI 职位匹配和日程安排。应用内消息和工作照片可供您、客户和授权支持管理员访问。'
                : (isMs
                ? 'Apabila anda menerima tempahan, anda menerima alamat perkhidmatan pelanggan dan arahan tempahan yang diperlukan untuk menyelesaikan kerja. Radius kawasan perkhidmatan dan ketersediaan anda digunakan untuk menggerakkan padanan pekerjaan dan penjadualan AI. Mesej dalam apl dan foto kerja boleh diakses oleh anda, pelanggan dan pentadbir sokongan yang diberi kuasa.'
                : 'When you accept a booking, you receive the customer’s service address and booking instructions needed to complete the job. Your service area radius and availability are used to power AI job matching and scheduling. In-app messages and photos are accessible to you, the customer, and authorised support administrators.'),
          ),
          const SizedBox(height: 12),

          _buildInfoCard(
            title: isZh
                ? '收益与付款'
                : (isMs ? 'Pendapatan dan pembayaran' : 'Earnings and payouts'),
            content: isZh
                ? '客户付款和服务商付款通过 Stripe 安全处理。本地生活服务助手记录交易参考、服务费、付款金额和结算状态，以维护您的收益仪表板和财务记录。'
                : (isMs
                ? 'Pembayaran pelanggan dan pembayaran penyedia diproses dengan selamat melalui Stripe. Pembantu Perkhidmatan Kehidupan Tempatan merekodkan rujukan transaksi, yuran perkhidmatan, jumlah pembayaran dan status penyelesaian untuk mengekalkan papan pemuka pendapatan dan rekod kewangan anda.'
                : 'Customer payments and provider payouts are processed securely through Stripe. Local Life Service Assistant records transaction references, service fees, payout amounts, and settlement statuses to maintain your earnings dashboard and financial records.'),
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