import Foundation

public struct TranslationBenchmarkSample: Equatable, Sendable {
    public let title: String
    public let text: String

    public init(title: String, text: String) {
        self.title = title
        self.text = text
    }
}

public enum TranslationBenchmarkSamples {
    public static func samples(sourceLanguage: String) -> [TranslationBenchmarkSample] {
        switch TranslationLanguage.normalizedName(sourceLanguage) {
        case "Korean":
            korean
        case "Japanese":
            japanese
        case "Simplified Chinese":
            simplifiedChinese
        case "Spanish":
            spanish
        case "German":
            german
        case "French":
            french
        case "Indonesian":
            indonesian
        case "Arabic":
            arabic
        default:
            english
        }
    }

    private static let english = [
        TranslationBenchmarkSample(title: "Short 1", text: "The deployment failed."),
        TranslationBenchmarkSample(title: "Short 2", text: "Please try again later."),
        TranslationBenchmarkSample(title: "Short 3", text: "twice"),
        TranslationBenchmarkSample(title: "Medium 1", text: "The deployment failed because the database URL was missing."),
        TranslationBenchmarkSample(title: "Medium 2", text: "Please summarize the release notes before the meeting starts."),
        TranslationBenchmarkSample(title: "Medium 3", text: "This button saves the current draft and closes the editor."),
        TranslationBenchmarkSample(title: "Long 1", text: "We delayed the rollout after the monitoring dashboard showed a sudden increase in checkout errors. The engineering team is validating the fix with a smaller traffic slice before enabling it for everyone."),
        TranslationBenchmarkSample(title: "Long 2", text: "The customer asked whether the invoice could be split by department. Finance can support that workflow, but the account owner needs to confirm the billing contacts first."),
        TranslationBenchmarkSample(title: "Long 3", text: "If the user copies a short fragment from a larger sentence, translate only the copied fragment. Use the surrounding screen context to choose the right meaning, but never translate unrelated visible text."),
    ]

    private static let korean = [
        TranslationBenchmarkSample(title: "Short 1", text: "배포가 실패했습니다."),
        TranslationBenchmarkSample(title: "Short 2", text: "잠시 후 다시 시도해 주세요."),
        TranslationBenchmarkSample(title: "Short 3", text: "두 번"),
        TranslationBenchmarkSample(title: "Medium 1", text: "데이터베이스 URL이 없어서 배포가 실패했습니다."),
        TranslationBenchmarkSample(title: "Medium 2", text: "회의가 시작되기 전에 릴리스 노트를 요약해 주세요."),
        TranslationBenchmarkSample(title: "Medium 3", text: "이 버튼은 현재 초안을 저장하고 편집기를 닫습니다."),
        TranslationBenchmarkSample(title: "Long 1", text: "모니터링 대시보드에서 결제 오류가 갑자기 증가한 것을 확인한 뒤 출시를 연기했습니다. 엔지니어링 팀은 전체 사용자에게 적용하기 전에 더 작은 트래픽 구간에서 수정 사항을 검증하고 있습니다."),
        TranslationBenchmarkSample(title: "Long 2", text: "고객은 청구서를 부서별로 나눌 수 있는지 물었습니다. 재무팀은 해당 워크플로를 지원할 수 있지만, 계정 담당자가 먼저 청구 연락처를 확인해야 합니다."),
        TranslationBenchmarkSample(title: "Long 3", text: "사용자가 긴 문장에서 짧은 조각만 복사했다면 복사한 조각만 번역하세요. 주변 화면 맥락은 올바른 의미를 고르는 데만 사용하고, 관련 없는 화면 텍스트는 번역하지 마세요."),
    ]

    private static let japanese = [
        TranslationBenchmarkSample(title: "Short 1", text: "デプロイに失敗しました。"),
        TranslationBenchmarkSample(title: "Short 2", text: "後でもう一度試してください。"),
        TranslationBenchmarkSample(title: "Short 3", text: "二回"),
        TranslationBenchmarkSample(title: "Medium 1", text: "データベースURLが不足していたため、デプロイに失敗しました。"),
        TranslationBenchmarkSample(title: "Medium 2", text: "会議が始まる前にリリースノートを要約してください。"),
        TranslationBenchmarkSample(title: "Medium 3", text: "このボタンは現在の下書きを保存し、エディターを閉じます。"),
        TranslationBenchmarkSample(title: "Long 1", text: "監視ダッシュボードでチェックアウトエラーの急増が確認されたため、ロールアウトを延期しました。エンジニアリングチームは全員に有効化する前に、小さなトラフィックで修正を検証しています。"),
        TranslationBenchmarkSample(title: "Long 2", text: "顧客は請求書を部門別に分割できるか確認しました。財務チームはそのワークフローに対応できますが、まずアカウント担当者が請求先を確認する必要があります。"),
        TranslationBenchmarkSample(title: "Long 3", text: "ユーザーが長い文から短い断片だけをコピーした場合は、その断片だけを翻訳してください。周囲の画面コンテキストは意味を選ぶためだけに使い、関係のない表示テキストは翻訳しないでください。"),
    ]

    private static let simplifiedChinese = [
        TranslationBenchmarkSample(title: "Short 1", text: "部署失败了。"),
        TranslationBenchmarkSample(title: "Short 2", text: "请稍后重试。"),
        TranslationBenchmarkSample(title: "Short 3", text: "两次"),
        TranslationBenchmarkSample(title: "Medium 1", text: "由于缺少数据库 URL，部署失败了。"),
        TranslationBenchmarkSample(title: "Medium 2", text: "请在会议开始前总结发布说明。"),
        TranslationBenchmarkSample(title: "Medium 3", text: "此按钮会保存当前草稿并关闭编辑器。"),
        TranslationBenchmarkSample(title: "Long 1", text: "监控仪表板显示结账错误突然增加后，我们推迟了发布。工程团队正在较小的流量范围内验证修复，然后再为所有用户启用。"),
        TranslationBenchmarkSample(title: "Long 2", text: "客户询问是否可以按部门拆分发票。财务可以支持该流程，但客户负责人需要先确认账单联系人。"),
        TranslationBenchmarkSample(title: "Long 3", text: "如果用户从较长的句子中只复制了一个短片段，只翻译复制的片段。使用周围的屏幕上下文来选择正确含义，但不要翻译无关的可见文本。"),
    ]

    private static let spanish = [
        TranslationBenchmarkSample(title: "Short 1", text: "La implementación falló."),
        TranslationBenchmarkSample(title: "Short 2", text: "Inténtalo de nuevo más tarde."),
        TranslationBenchmarkSample(title: "Short 3", text: "dos veces"),
        TranslationBenchmarkSample(title: "Medium 1", text: "La implementación falló porque faltaba la URL de la base de datos."),
        TranslationBenchmarkSample(title: "Medium 2", text: "Resume las notas de la versión antes de que empiece la reunión."),
        TranslationBenchmarkSample(title: "Medium 3", text: "Este botón guarda el borrador actual y cierra el editor."),
        TranslationBenchmarkSample(title: "Long 1", text: "Retrasamos el lanzamiento después de que el panel de monitoreo mostrara un aumento repentino de errores de pago. El equipo de ingeniería está validando la corrección con una porción menor del tráfico antes de activarla para todos."),
        TranslationBenchmarkSample(title: "Long 2", text: "El cliente preguntó si la factura podía dividirse por departamento. Finanzas puede admitir ese flujo, pero el responsable de la cuenta debe confirmar primero los contactos de facturación."),
        TranslationBenchmarkSample(title: "Long 3", text: "Si el usuario copia un fragmento corto de una oración más larga, traduce solo el fragmento copiado. Usa el contexto de pantalla cercano para elegir el significado correcto, pero nunca traduzcas texto visible no relacionado."),
    ]

    private static let german = [
        TranslationBenchmarkSample(title: "Short 1", text: "Die Bereitstellung ist fehlgeschlagen."),
        TranslationBenchmarkSample(title: "Short 2", text: "Bitte versuche es später erneut."),
        TranslationBenchmarkSample(title: "Short 3", text: "zweimal"),
        TranslationBenchmarkSample(title: "Medium 1", text: "Die Bereitstellung ist fehlgeschlagen, weil die Datenbank-URL fehlte."),
        TranslationBenchmarkSample(title: "Medium 2", text: "Bitte fasse die Versionshinweise vor Beginn des Meetings zusammen."),
        TranslationBenchmarkSample(title: "Medium 3", text: "Diese Schaltfläche speichert den aktuellen Entwurf und schließt den Editor."),
        TranslationBenchmarkSample(title: "Long 1", text: "Wir haben die Einführung verschoben, nachdem das Monitoring-Dashboard einen plötzlichen Anstieg von Checkout-Fehlern zeigte. Das Engineering-Team validiert die Korrektur mit einem kleineren Traffic-Anteil, bevor sie für alle aktiviert wird."),
        TranslationBenchmarkSample(title: "Long 2", text: "Der Kunde fragte, ob die Rechnung nach Abteilung aufgeteilt werden kann. Finance kann diesen Ablauf unterstützen, aber der Account Owner muss zuerst die Rechnungskontakte bestätigen."),
        TranslationBenchmarkSample(title: "Long 3", text: "Wenn der Benutzer ein kurzes Fragment aus einem längeren Satz kopiert, übersetze nur das kopierte Fragment. Nutze den umgebenden Bildschirmkontext, um die richtige Bedeutung zu wählen, aber übersetze niemals nicht zugehörigen sichtbaren Text."),
    ]

    private static let french = [
        TranslationBenchmarkSample(title: "Short 1", text: "Le déploiement a échoué."),
        TranslationBenchmarkSample(title: "Short 2", text: "Veuillez réessayer plus tard."),
        TranslationBenchmarkSample(title: "Short 3", text: "deux fois"),
        TranslationBenchmarkSample(title: "Medium 1", text: "Le déploiement a échoué parce que l'URL de la base de données manquait."),
        TranslationBenchmarkSample(title: "Medium 2", text: "Veuillez résumer les notes de version avant le début de la réunion."),
        TranslationBenchmarkSample(title: "Medium 3", text: "Ce bouton enregistre le brouillon actuel et ferme l'éditeur."),
        TranslationBenchmarkSample(title: "Long 1", text: "Nous avons retardé le déploiement après que le tableau de bord de surveillance a montré une augmentation soudaine des erreurs de paiement. L'équipe d'ingénierie valide le correctif sur une part de trafic plus petite avant de l'activer pour tout le monde."),
        TranslationBenchmarkSample(title: "Long 2", text: "Le client a demandé si la facture pouvait être divisée par département. L'équipe Finance peut prendre en charge ce flux, mais le responsable du compte doit d'abord confirmer les contacts de facturation."),
        TranslationBenchmarkSample(title: "Long 3", text: "Si l'utilisateur copie un court fragment d'une phrase plus longue, traduisez uniquement le fragment copié. Utilisez le contexte d'écran autour pour choisir le bon sens, mais ne traduisez jamais le texte visible non lié."),
    ]

    private static let indonesian = [
        TranslationBenchmarkSample(title: "Short 1", text: "Deployment gagal."),
        TranslationBenchmarkSample(title: "Short 2", text: "Silakan coba lagi nanti."),
        TranslationBenchmarkSample(title: "Short 3", text: "dua kali"),
        TranslationBenchmarkSample(title: "Medium 1", text: "Deployment gagal karena URL database tidak ada."),
        TranslationBenchmarkSample(title: "Medium 2", text: "Tolong rangkum catatan rilis sebelum rapat dimulai."),
        TranslationBenchmarkSample(title: "Medium 3", text: "Tombol ini menyimpan draf saat ini dan menutup editor."),
        TranslationBenchmarkSample(title: "Long 1", text: "Kami menunda peluncuran setelah dashboard pemantauan menunjukkan peningkatan mendadak pada error checkout. Tim engineering sedang memvalidasi perbaikan dengan porsi traffic yang lebih kecil sebelum mengaktifkannya untuk semua orang."),
        TranslationBenchmarkSample(title: "Long 2", text: "Pelanggan bertanya apakah invoice dapat dipisahkan berdasarkan departemen. Finance dapat mendukung alur tersebut, tetapi account owner perlu mengonfirmasi kontak penagihan terlebih dahulu."),
        TranslationBenchmarkSample(title: "Long 3", text: "Jika pengguna menyalin fragmen pendek dari kalimat yang lebih panjang, terjemahkan hanya fragmen yang disalin. Gunakan konteks layar sekitar untuk memilih makna yang tepat, tetapi jangan pernah menerjemahkan teks terlihat yang tidak terkait."),
    ]

    private static let arabic = [
        TranslationBenchmarkSample(title: "Short 1", text: "فشل النشر."),
        TranslationBenchmarkSample(title: "Short 2", text: "يرجى المحاولة مرة أخرى لاحقًا."),
        TranslationBenchmarkSample(title: "Short 3", text: "مرتين"),
        TranslationBenchmarkSample(title: "Medium 1", text: "فشل النشر لأن عنوان URL لقاعدة البيانات كان مفقودًا."),
        TranslationBenchmarkSample(title: "Medium 2", text: "يرجى تلخيص ملاحظات الإصدار قبل بدء الاجتماع."),
        TranslationBenchmarkSample(title: "Medium 3", text: "يحفظ هذا الزر المسودة الحالية ويغلق المحرر."),
        TranslationBenchmarkSample(title: "Long 1", text: "أجلنا الطرح بعد أن أظهرت لوحة المراقبة زيادة مفاجئة في أخطاء الدفع. يتحقق فريق الهندسة من الإصلاح على جزء أصغر من حركة المرور قبل تفعيله للجميع."),
        TranslationBenchmarkSample(title: "Long 2", text: "سأل العميل ما إذا كان يمكن تقسيم الفاتورة حسب القسم. يمكن لفريق المالية دعم هذا المسار، لكن على مسؤول الحساب تأكيد جهات اتصال الفوترة أولًا."),
        TranslationBenchmarkSample(title: "Long 3", text: "إذا نسخ المستخدم جزءًا قصيرًا من جملة أطول، فترجم الجزء المنسوخ فقط. استخدم سياق الشاشة المحيط لاختيار المعنى الصحيح، لكن لا تترجم أي نص مرئي غير ذي صلة."),
    ]
}
