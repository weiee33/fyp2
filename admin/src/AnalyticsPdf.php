<?php
declare(strict_types=1);
namespace LocalLife;

/** Server-generated report from the same authorized, filtered result as the page. */
final class AnalyticsPdf
{
    public static function render(array $data): string
    {
        require_once dirname(__DIR__).'/vendor/autoload.php';
        $fontRoot=realpath(dirname(__DIR__,2).'/assets/fonts');
        if ($fontRoot===false) { throw new ApiException(503,'Report fonts are unavailable. Please contact the site administrator.'); }
        $cache=sys_get_temp_dir().'/homeserve-pdf-'.bin2hex(random_bytes(12));
        if (!mkdir($cache,0700)) { throw new ApiException(503,'Unable to prepare the report. Please try again.'); }
        try {
            $options=new \Dompdf\Options([
                'isRemoteEnabled'=>false,'isPhpEnabled'=>false,'isJavascriptEnabled'=>false,
                'isFontSubsettingEnabled'=>true,'chroot'=>[$fontRoot],
                'tempDir'=>$cache,'fontDir'=>$cache,'fontCache'=>$cache,
            ]);
            $pdf=new \Dompdf\Dompdf($options);
            ob_start();
            try {
                require dirname(__DIR__).'/views/analytics-pdf.php';
                $html=ob_get_contents();
            } finally {
                ob_end_clean();
            }
            $pdf->loadHtml($html,'UTF-8');
            $pdf->setPaper('A4');
            $pdf->render();
            $font=$pdf->getFontMetrics()->getFont('DejaVu Sans');
            $pdf->getCanvas()->page_text(475,810,'Page {PAGE_NUM} / {PAGE_COUNT}',$font,8,[0.4,0.4,0.4]);
            return $pdf->output();
        } finally {
            // Release renderer/font streams before unlinking files on Windows.
            unset($pdf);
            gc_collect_cycles();
            // Only renderer files in this request's unpredictable private directory.
            $files=new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($cache,\FilesystemIterator::SKIP_DOTS),
                \RecursiveIteratorIterator::CHILD_FIRST
            );
            foreach ($files as $file) {
                if ($file->isDir() && !$file->isLink()) { rmdir($file->getPathname()); }
                else { unlink($file->getPathname()); }
            }
            unset($files,$file);
            rmdir($cache);
        }
    }
}
