/* Rawi landing page: all copy (AR/EN) and demo data. */
var P='⁦$XX⁩';
/* ====================== copy ====================== */
var T={
ar:{lang:'English',nav1:'المزايا',nav2:'القاموس والعبارات',nav3:'الأوامر',nav4:'السعر',nav5:'أسئلة',get:'بيع مسبق \u2066$29\u2069',see:'شوف وش يسوي',
 h1:'تكلّم. <em>راوي</em> يكتب.',
 sub:'اضغط مفتاحك وتكلّم ثم اتركه. يطلع نص عربي وإنجليزي نظيف عند المؤشر، في أي تطبيق.',
 demoT:'جرّب بنفسك',typedL:'اللي يكتبه راوي',heardL:'اللي سمعه',
 ph:'اكتب مثل ما تتكلم، مثلاً: اممم نخلص الأحد لا قصدي الاثنين',empty:'اللي يكتبه راوي يطلع هنا.',samples:'عيّنات',
 
 did:'وش سوّى:',fill:function(n){return 'حذف '+n+' من الحشو'},corr:'طبّق تصحيحك',list:'حوّلها لقائمة',punct:'ضبط الترقيم',
 fine:'هذا العرض يقلّد تنظيف راوي داخل المتصفح. التطبيق نفسه يحوّل الصوت بـ Whisper وينظّفه بنموذج لغوي.',
 h1t:'اضغط',h1p:'اضغط مفتاح الإملاء وراوي يبدأ يسجّل. Esc يلغي.',spk:'تكلّم',h2t:'تكلّم',h2p:'عربي، إنجليزي، أو الاثنين. بدون ما تختار لغة.',rel:'اترك',h3t:'اترك',h3p:'بعد حوالي ثانية يطلع النص عند المؤشر.',
 fxH:'تكلّم مثل ما تتكلم. يطلع مرتّب.',fxP:'راوي يشيل الحشو، يطبّق تصحيحك، يرتّب القوائم، ويخلّي كل لغة بحروفها.',
 fxTabs:['الحشو','التصحيح','القوائم','لغتين'],said:'اللي قلته',typedS:'اللي ينكتب',
 fxWhy:['اممم وآه وكلمات البداية مثل «يعني» تنحذف.','قل «الثلاثاء، لا قصدي الأربعاء» وتطلع الأربعاء بس.','قل أولاً وثانياً وثالثاً، وتطلع لك قائمة مرقّمة.','العربي يبقى عربي والإنجليزي يبقى إنجليزي، حتى داخل جملة وحدة. ما يترجم شي.'],
 bnH:'يعرف كلماتك، ويكتب على قد المكان.',bnP:'قاموس يتعلّم أسماءك، وعبارات تتوسّع، وقواعد لكل تطبيق.',
 deT:'يكتب لكل مكان بأسلوبه',deP:'تحط قاعدة لتطبيق أو صفحة أو حقل. رسالة Slack تطلع فقرة قصيرة، وتذكرة Jira تطلع ملخص وتفاصيل.',
 deN:'أمثلة على القواعد. القاعدة الأدق تفوز: الحقل ثم الصفحة ثم التطبيق.',
 deSaid:'قل للفريق إن النسخة التجريبية تنزل الخميس وملاحظات الإصدار الجمعة',
 dcT:'قاموس يتعلّم',dcP:'صحّح اسماً في مستندك وراوي يكتبه بطريقتك المرة الجاية. وتقدر تضيف كلماتك بنفسك.',
 dcS:function(w){return 'قل لـ '+w+' يراجع العرض قبل الاجتماع'},dcBtn:'صحّحتها إلى Rawi',dcOk:'تعلّمها. المرة الجاية تنكتب صح.',dcReset:'ابدأ من جديد',
 snT:'كلمة مفتاحية',snP:'تتوسّع بعد التنظيف، فما يخرّب الروابط ولا العناوين.',snSaid:'قل',
 cmH:'من الكلام إلى الفعل، وخلّص شغلك!',cmP:'راوي يطابق عبارات مكتوبة عندك على الماك، ويعرض لك وش بيسوي، وينتظرك توافق. ما فيه نموذج يخمّن نيّتك.',
 cmSaid:'قلت',cmWill:'راوي بيسوي',cmRun:'نفّذ',cmCancel:'إلغاء',cmDone:'نُفّذ. هذا عرض تجريبي ما أنشأ شي فعلاً.',cmOff:'مقفل حتى تضبطه',
 cmTimes:'يقرأ الوقت من كلامك: «بكرة الساعة تسعة»، «الثلاثاء الجاية 4 العصر»، «بعد 20 دقيقة».',
 tfH:'انسخ نص. وقل وش تبي له.',tfP:'اضغط <span dir="ltr"><kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>T</kbd></span> وقل وش تبي، ويُكتب التعديل مكان تحديدك. خمسة جاهزة، وأي شي ثاني تقوله ينفّذه مثل ما قلته.',
 tfA:'النص المنسوخ',tfB:'اللي يُكتب',tfN:'أمثلة. التعديل ينتقل للحافظة أيضاً، ولو فشل شي تبقى حافظتك كما هي.',tfSay:'قل',tfFree:'اكتبها بحرية',
 tfHint:'وأي شي ثاني، مثل «حوّلها لثلاث نقاط».',
 inK:'صوتك',inH:'افهم نفسك أكثر من سجل كلامك.',inP:'كل رقم محسوب من السجل وليس تخميناً. احذف إملاء وتتغيّر الأرقام.',
 inC:'شاشة الإحصاءات في التطبيق. أرقام تجريبية.',vcC:'شاشة «صوتك» في التطبيق: ملف صوتك وعباراتك وكلماتك.',imgVc:'شاشة صوتك في راوي: ملف الصوت، العبارة المتكررة، أكثر كلمة، وقت الذروة، والحشو',vcProf:'ملف صوتك',vcCatch:'عبارتك المتكررة',vcWord:'أكثر كلمة تستخدمها',vcFixed:'أكثر كلمة صحّحتها',vcTaught:'علّمتها لراوي.',vcFill:'حشوك المفضّل',vcOut:'حذفه راوي 41 مرة.',vcWords:'كلمة',vcLong:'أطول إملاء',vcNTaught:'كلمات علّمتها لراوي',vcFine:'عيّنة من شاشة «صوتك» في التطبيق. محسوبة من سجلك على جهازك، والنص المكتوب يكتبه نموذج محلي. الأرقام تجريبية.',hiC:'السجل: اللي سمعه راوي بجانب اللي كتبه. أرقام وأمثلة تجريبية.',
 inF:['<b>ابحث في الاثنين.</b> تذكر اللي قلته مو اللي طلع.','<b>«استخدم ما قلته»</b> يرجّع كلامك الأصلي لو نظّف شي ما تبيه.','<b>مشفّر على ماكك</b> ويُحذف بعد 90 يوماً. ما يُسجَّل مدير كلمات المرور ولا الرسائل الخاصة.'],
 imgIn:'إحصاءات راوي: كلمات في الدقيقة، الكلمات المُملاة، أين تُملي، والسلسلة اليومية',imgHi:'سجل راوي: اللي سمعه بجانب اللي كُتب',
 pvH:'بدون حساب. بدون تتبّع. ومفتاحك أنت.',
 pv:[['ما فيه حساب','ما فيه تسجيل دخول ولا تحليلات ولا تقارير أعطال.'],['مفتاح Groq حقك','الصوت والتنظيف يمرّون على مفتاحك المجاني. المفتاح يبقى على ماكك فقط.'],['ما يضيع إملاء','لو Groq ما اشتغل، نفس التسجيل يتحوّل بـ whisper.cpp على ماكك.'],['أو بدون إنترنت','شغّله كله على الماك، وما يطلع شي من جهازك. التسجيل يُحذف بعد ما يُكتب النص.']],
 ofBadge:'بيع مسبق لأول 10 مشترين',ofH:'خذ راوي مرة وحدة، وهو <mark>لك للأبد</mark>',ofNote:'سعر الإطلاق لأول 10 مشترين فقط.',ofBuy:'احجز نسختك بـ $29',ofVibe:'أو ابنِه بنفسك مجاناً (Vibe)',ofFine:'نسخة أولية: macOS يطلب موافقتك مرة وحدة عند أول فتح، بالنقر الأيمن ثم «فتح». ما تحتاج أكثر.',ofBy:'صُنع بواسطة',phL:'فلسفتي في التسعير',phH:'ادفع مرة وحدة، وهو لك للأبد.',phP:'راوي يشتغل على جهازك، بدون خوادم مني وبدون فاتورة على كل استخدام. فالاشتراك ما له معنى.',phU:['<b>بدون اشتراك.</b> تدفع مرة وحدة.','<b>بدون حساب وبدون تتبّع.</b> كلامك يبقى لك.','<b>مفتاح Groq المجاني حقك،</b> أو شغّله كله على ماكك.'],mcH:'أو... ابنِه بنفسك مجاناً',mcP:'أؤمن بالبناء بالذكاء الاصطناعي، وهكذا بنيت راوي. تبي توفّر وقتك؟ شوف كم يكلّفك.',mcBuild:'ساعات البناء (عندي)',mcMaint:'ساعات الصيانة تقريباً',mcRate:'سعر ساعتك',mcTot:'وقتك يساوي (البناء + سنة صيانة)',mcSave:'توفّر مع البيع المسبق',mcHrs2:'يعني {h} ساعة من وقتك، مقابل دفعة وحدة.',prH:'ادفع مرة وحدة، وهو لك.',prP:'بدون اشتراك. اختر نسخة التطبيق، أو النسخة اللي معها الكود.',
 p1:'راوي',p1u:['تطبيق Rawi.app لأجهزة Apple silicon (macOS 14 أو أحدث)','عربي وإنجليزي والاثنين في جملة','أوامر، قاموس، عبارات، تحويلات','سجل وإحصاءات'],
 p2:'راوي + الكود',p2u:['كل شي في راوي','الكود المصدري كاملاً (Swift)','عدّله مع Claude Code أو أي مساعد برمجة','ابنِه بنفسك بأمر make install'],
 once:'دفعة وحدة',pbuy1:'اشترِ التطبيق',pbuy2:'اشترِ التطبيق مع الكود',ph:'سعر مؤقت',cT:'أو خذه مجاناً: ابنِه بنفسك',cP:'ما يكلّفك اشتراك. بس يكلّفك وقتك. احسب كم تدفع لو بنيته بنفسك.',cH:'ساعات البناء',cR:'سعر ساعتك بالدولار',cB:'وقتك لو بنيته',cBuy:'راوي',cS:'توفّر',cN:'تقدير منك أنت، مو عرض سعر. الافتراضي ٨٠ ساعة، لأن التسجيل والتحويل والتنظيف واللصق في كل تطبيق مو شغل ليلة.',first10:'سعر الإطلاق لأول 10 مشترين',buyN:'روابط الشراء تُضاف عند الإطلاق. الأسعار الظاهرة مؤقتة.',
 inc:['فقرات، واحدة لكل فكرة','الحافظة تحتفظ بآخر نص','شريط صغير يوضّح مستوى صوتك','الإملاء بدون يدين بنقرتين','فتح عند تسجيل الدخول','نسخة احتياطية على الماك'],
 vbT:'عدّله بنفسك',vbP:'مع نسخة الكود، قل لمساعدك البرمجي وش تبي يتغيّر. أمثلة:',
 vb:['غيّر مفتاح التسجيل إلى Right Option','أضف قاعدة لتطبيق Notion','خلّ الشريط يظهر أعلى الشاشة','أضف أمراً يفتح مشروعي'],
 fqH:'أسئلة شائعة',
 fq:[['وش الأجهزة المدعومة؟','أجهزة ماك بمعالج Apple silicon وmacOS 14 أو أحدث.'],['ليش التطبيق غير موقّع؟','التوقيع من Apple يحتاج حساب مطوّر مدفوع. أول مرة افتحه بالنقر الأيمن ثم «فتح». ومع التحديث تمنح الأذونات من جديد.'],['أحتاج مفتاح Groq؟','نعم، لو تبي السرعة الافتراضية. المفتاح مجاني وتسوّيه من console.groq.com. أو شغّله كله على ماكك بدون إنترنت.'],['هل يحفظ صوتي؟','لا. التسجيل يُحذف بعد ما يُكتب النص. السجل نصوص فقط، مشفّر على ماكك.'],['وش الفرق بين النسختين؟','نفس التطبيق. نسخة الكود تعطيك مشروع Swift كامل تعدّله مع مساعدك البرمجي.'],['هل يترجم كلامي؟','لا أبداً. العربي يبقى عربي والإنجليزي يبقى إنجليزي. الترجمة تحويل تطلبه بنفسك.']],
 copy:'© 2026 راوي',made:'صُنع بواسطة'},
en:{lang:'العربية',nav1:'Features',nav2:'Dictionary and snippets',nav3:'Commands',nav4:'Pricing',nav5:'FAQ',get:'Pre-sale $29',see:'See what it does',
 h1:'Speak. <em>Rawi</em> types.',
 sub:'Hold a key, talk, release. Clean Arabic and English text lands at your cursor, in any app.',
 demoT:'Try it yourself',typedL:'What Rawi types',heardL:'Heard',
 ph:'Type like you talk, for example: um let\'s ship sunday no wait monday',empty:'What Rawi types shows up here.',samples:'Samples',
 
 did:'What it did:',fill:function(n){return 'Removed '+n+' filler'+(n>1?'s':'')},corr:'Applied your correction',list:'Made it a list',punct:'Fixed punctuation',
 fine:'This demo imitates Rawi\'s cleanup in your browser. The app itself transcribes with Whisper and polishes with a language model.',
 h1t:'Hold',h1p:'Hold your dictation key and Rawi starts listening. Esc cancels.',spk:'Speak',h2t:'Speak',h2p:'Arabic, English, or both. No language switch.',rel:'Release',h3t:'Release',h3p:'About a second later, the text is at your cursor.',
 fxH:'Talk the way you talk. It lands tidy.',fxP:'Rawi removes fillers, applies your corrections, lines up lists, and keeps each language in its own script.',
 fxTabs:['Fillers','Corrections','Lists','Two languages'],said:'What you said',typedS:'What gets typed',
 fxWhy:['Um, uh, and lead-ins like "so" are dropped.','Say "Tuesday, sorry, I mean Wednesday". Only Wednesday lands.','Say first, second, third. You get a numbered list.','Arabic stays Arabic and English stays English, even inside one sentence. Nothing is translated.'],
 bnH:'It knows your words, and writes for the place.',bnP:'A dictionary that learns your names, phrases that expand, and a rule for each app.',
 deT:'Writes for where it lands',deP:'Set a rule per app, page or field. A Slack message becomes one short paragraph. A Jira ticket gets a summary and details.',
 deN:'Example rules. The most specific rule wins: field, then page, then app.',
 deSaid:'tell the team the beta ships thursday and the release notes follow on friday',
 dcT:'A dictionary that learns',dcP:'Fix a name in your document and Rawi spells it your way next time. You can add terms yourself too.',
 dcS:function(w){return 'ask '+w+' to review the deck before the meeting'},dcBtn:'I corrected it to Rawi',dcOk:'Learned. Next time it is spelled right.',dcReset:'Start over',
 snT:'A few words, the whole thing',snP:'They expand after cleanup, so URLs and addresses are never mangled.',snSaid:'You say',
 cmH:'Some dictation isn\'t text. Say it and it happens.',cmP:'Rawi matches a phrase list on your Mac, shows what it will do, then waits for you. No model guesses your intent.',
 cmSaid:'You said',cmWill:'Rawi will',cmRun:'Run',cmCancel:'Cancel',cmDone:'Done. This is a demo, so nothing was actually created.',cmOff:'Off until you set it up',
 cmTimes:'It reads times from your words: "tomorrow at 9", "next Tuesday at 4pm", "in 20 minutes".',
 tfH:'Copy text. Say what to do with it.',tfP:'Hold <span dir="ltr"><kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>T</kbd></span>, say what you want, and the rewrite is typed over your selection. Five ship built in. Say anything else and it is used as you said it.',
 tfA:'Text on your clipboard',tfB:'What gets typed',tfN:'Examples. The rewrite also stays on the clipboard, and if anything fails your clipboard is left exactly as it was.',tfSay:'Say',tfFree:'Say it freely',
 tfHint:'Or anything else, like "turn this into three bullets".',
 inK:'Your voice',inH:'Understand yourself more via your speech history.',inP:'Every number is counted from your History, not guessed. Delete a dictation and the numbers change.',
 inC:'The Insights screen in the app, with sample numbers.',vcC:'The Your voice screen in the app: your voice profile, phrases and words.',imgVc:'Rawi Your voice screen: voice profile, catchphrase, most used word, peak time and filler',vcProf:'Voice profile',vcCatch:'Catchphrase',vcWord:'Most used word',vcFixed:'Most corrected word',vcTaught:'You taught Rawi this spelling.',vcFill:'Your filler',vcOut:'Rawi took it out 41 times.',vcWords:'words',vcLong:'Longest dictation',vcNTaught:'Words you taught Rawi',vcFine:'A sample of the app\'s Your voice screen. It is counted from your history on your Mac, and the written profile comes from a local model. Numbers are sample data.',hiC:'History: what Rawi heard next to what it typed. Sample entries.',
 inF:['<b>Search both.</b> You remember what you said, not what came out.','<b>Use what I said</b> brings your original words back if cleanup changed something you wanted.','<b>Encrypted on your Mac</b> and removed after 90 days. Password managers and private messages are never recorded.'],
 imgIn:'Rawi Insights: words per minute, words dictated, where you dictate and a daily streak',imgHi:'Rawi History: what was heard next to what was typed',
 pvH:'No account. No telemetry. Your own key.',
 pv:[['No account','No sign-in, no analytics, no crash reports.'],['Your Groq key','Speech and polish go through your own free key. The key stays on your Mac.'],['Nothing gets lost','If Groq is unreachable, the same audio is transcribed by whisper.cpp on your Mac.'],['Or fully offline','Run it all on the Mac and nothing leaves your machine. Audio is deleted once the text is typed.']],
 ofBadge:'Pre-sale for the first 10 buyers',ofH:'Get Rawi once, and it\'s <mark>yours forever</mark>',ofNote:'Launch price for the first 10 buyers only.',ofBuy:'Reserve my copy for $29',ofVibe:'Or build it yourself for free (Vibe)',ofFine:'Early version: macOS asks for your OK once on first open. Right-click, then Open. That is all it takes.',ofBy:'Made by',phL:'My pricing philosophy',phH:'Pay once, and it\'s yours forever.',phP:'Rawi runs on your Mac, with no servers from me and no bill for every use. So a subscription makes no sense.',phU:['<b>No subscription.</b> You pay once.','<b>No account, no telemetry.</b> Your speech stays yours.','<b>Your own free Groq key,</b> or run it all on your Mac.'],mcH:'Or... build it yourself for free',mcP:'I believe in building with AI, and that is how I built Rawi. Want to save your time? See what it would cost you.',mcBuild:'Build hours (mine)',mcMaint:'Maintenance, roughly',mcRate:'Your hourly rate',mcTot:'Your time is worth (build + 1 year of upkeep)',mcSave:'You save with the pre-sale',mcHrs2:'That is {h} hours of your time, against a one-time payment.',prH:'Pay once. It\'s yours.',prP:'No subscription. Take the app, or the app with its source code.',
 p1:'Rawi',p1u:['Rawi.app for Apple silicon Macs (macOS 14 or later)','Arabic, English, and both in one sentence','Commands, dictionary, snippets, transforms','History and insights'],
 p2:'Rawi + Source',p2u:['Everything in Rawi','The full Swift source code','Change it with Claude Code or any coding assistant','Build it yourself with make install'],
 once:'one-time',pbuy1:'Get App',pbuy2:'Get App + Source',ph:'placeholder price',cT:'Or take it for free: build it yourself',cP:'No subscription needed. It just costs your time. Work out what building it would cost you.',cH:'Hours to build',cR:'Your hourly rate in dollars',cB:'Your time, if you build it',cBuy:'Rawi',cS:'You save',cN:'Your own estimate, not a quote. It starts at 80 hours, because recording, transcribing, cleaning up and pasting into every app is not a one-night job.',first10:'launch price for the first 10 buyers',buyN:'Purchase links are added at launch. Prices shown are placeholders.',
 inc:['Paragraphs, one per idea','Clipboard keeps the last text','A small pill with a live level meter','Hands-free dictation with a double tap','Launch at login','On-Mac fallback if the network drops'],
 vbT:'Change it yourself',vbP:'With the source edition, tell your coding assistant what you want different. Ideas:',
 vb:['Change the record key to Right Option','Add a rule for Notion','Show the pill at the top of the screen','Add a command that opens my project'],
 fqH:'Questions',
 fq:[['Which Macs does it run on?','Apple silicon Macs on macOS 14 or later.'],['Why is the app unsigned?','Apple notarization needs a paid developer account. On first launch, right-click the app and choose Open. After an update you grant the permissions again.'],['Do I need a Groq key?','For the default fast path, yes. The key is free from console.groq.com. Or run everything on your Mac, offline.'],['Does it keep my voice?','No. The recording is deleted once the text is typed. History holds text only, encrypted on your Mac.'],['What is the difference between the editions?','Same app. The source edition adds the full Swift project to change with your coding assistant.'],['Does it translate what I say?','Never. Arabic stays Arabic and English stays English. Translating is a transform you ask for yourself.']],
 copy:'© 2026 Rawi',made:'Made by'}
};

/* ====================== data ====================== */
var SAMPLES=[
 {n:{ar:'تصحيح بالعربي',en:'Arabic correction'},l:'ar',t:'اممم يعني نخلص التقرير يوم الثلاثاء لا قصدي الأربعاء ونرسله للعميل'},
 {n:{ar:'تصحيح بالإنجليزي',en:'English correction'},l:'en',t:"so um let's meet on tuesday sorry I mean wednesday at 3 o'clock"},
 {n:{ar:'عربي وإنجليزي',en:'Arabic + English'},l:'ar',t:'اممم خلنا نأجل الـ standup لين نخلص الـ deck ونرسله للعميل'},
 {n:{ar:'قائمة',en:'A list'},l:'en',t:'um three things for the launch first write the release notes second record the demo third ping the beta list'}
];
var FX={
 ar:['اممم يعني خلنا نرسل العرض للعميل بكرة','الاجتماع يوم الثلاثاء لا قصدي الأربعاء الساعة ثلاثة','عندنا ثلاث نقاط للإطلاق أولاً نكتب ملاحظات الإصدار ثانياً نصور العرض ثالثاً نبلغ قائمة التجربة','اممم خلنا نأجل الـ standup لبعد الظهر ونرسل الـ deck للعميل'],
 en:['um so I think uh we should ship it on friday','let\'s meet on tuesday sorry I mean wednesday at 3 o\'clock','three things before launch first write the release notes second record the demo third ping the beta list','um send the deck للعميل after the standup']
};
var DEST={
 said:{ar:'قل للفريق إن النسخة التجريبية تنزل الخميس وملاحظات الإصدار الجمعة',en:'tell the team the beta ships thursday and the release notes follow on friday'},
 ar:{Slack:'تنبيه: النسخة التجريبية تنزل الخميس وملاحظات الإصدار الجمعة',Jira:'الملخص: صدور النسخة التجريبية الخميس\nالتفاصيل: ملاحظات الإصدار يوم الجمعة.',Mail:'مرحباً فريق،\n\nستصدر النسخة التجريبية يوم الخميس، وتليها ملاحظات الإصدار يوم الجمعة.\n\nشكراً،',Docs:'تصدر النسخة التجريبية يوم الخميس، وتليها ملاحظات الإصدار يوم الجمعة.'},
 en:{Slack:'heads up: beta ships Thursday, release notes follow Friday',Jira:'Summary: Beta ships Thursday\nDetails: Release notes follow on Friday.',Mail:'Hi team,\n\nThe beta ships Thursday, and the release notes follow on Friday.\n\nThanks,',Docs:'The beta ships on Thursday, and the release notes follow on Friday.'}
};
var SNIP=[
 {k:{ar:'إيميل شغلي',en:'my work email'},v:'you@company.com',s:{ar:'ارسل الملف على إيميل شغلي',en:'send the file to my work email'},sv:{ar:'ارسل الملف على ',en:'send the file to '}},
 {k:{ar:'رابط جدولي',en:'my calendar'},v:'cal.example.com/you',s:{ar:'احجز وقت من رابط جدولي',en:'book a time on my calendar'},sv:{ar:'احجز وقت من ',en:'book a time on '}},
 {k:{ar:'توقيعي',en:'my sign off'},v:'Best,\nYour Name',s:{ar:'اختم الرسالة بـ توقيعي',en:'close with my sign off'},sv:{ar:'اختم الرسالة بـ ',en:'close with '}}
];
var CMDS=[
 {k:'ask Claude',off:0,said:{ar:['ask Claude','كيف أسعّر تطبيق بدفعة وحدة'],en:['ask Claude','how should I price a one-time app']},will:{ar:'افتح claude.ai في محادثة جديدة والسؤال مكتوب فيها. ما يُرسل شي لين تضغط Return.',en:'Open claude.ai in a new chat with your question already typed. Nothing is sent until you press return.'}},
 {k:'remind me to',off:0,said:{ar:['remind me to','أرسل العرض يوم الخميس الساعة 2'],en:['remind me to','send the deck on Thursday at 2']},will:{ar:'أضف «أرسل العرض» إلى قائمة التذكيرات، يوم الخميس الساعة 2 م.',en:'Add "send the deck" to your Reminders list, on Thursday at 2 pm.'}},
 {k:'capture idea',off:1,said:{ar:['capture idea','صفحة هبوط بالصوت أولاً'],en:['capture idea','voice-first landing page']},will:{ar:'أضف صفحة «صفحة هبوط بالصوت أولاً» إلى قاعدة Notion حقك.',en:'Add a page "voice-first landing page" to your Notion backlog.'}},
 {k:'new ticket',off:1,said:{ar:['new ticket','الدفع يفشل في الجوال'],en:['new ticket','checkout fails on mobile']},will:{ar:'افتح نموذج Jira والملخص مكتوب فيه. ما تُنشأ تذكرة لين تحفظها هناك.',en:'Open Jira\'s create form with the summary filled in. Nothing is created until you save it there.'}},
 {k:'deep work',off:1,said:{ar:['deep work',''],en:['deep work','']},will:{ar:'افتح التطبيق اللي تختاره، مثل Shortcuts، لروتين تركيزك.',en:'Open the app you choose, such as Shortcuts, for your focus routine.'}}
];
var TF_SRC="so I was thinking we should maybe move the launch, because the docs aren't ready and Sara is out until the 14th, and honestly the demo still crashes sometimes, so yeah maybe push it a week?";
var TF=[
 {n:{ar:'تلميع',en:'Polish'},o:"I think we should move the launch. The docs aren't ready, Sara is out until the 14th, and the demo still crashes sometimes. Could we push it by a week?"},
 {n:{ar:'حوّلها لأمر لمساعد ذكي',en:'Turn this into a prompt'},o:"Should we delay our launch by a week? Context: the docs aren't ready, Sara is out until the 14th, and the demo sometimes crashes. Give a recommendation and the main reasons."},
 {n:{ar:'اختصرها',en:'Make it shorter'},o:"Let's push the launch a week: the docs aren't ready, Sara is out until the 14th, and the demo still crashes."},
 {n:{ar:'ترجم للعربية',en:'Translate to Arabic'},ar:1,o:"أعتقد أننا يجب أن نؤجل الإطلاق أسبوعاً، فالوثائق غير جاهزة، وسارة في إجازة حتى الرابع عشر، والعرض التجريبي ما زال يتعطل أحياناً."},
 {n:{ar:'رد بأسلوبي',en:'Reply in my tone'},o:"Makes sense to me. A week gives us time to finish the docs and get Sara back. Want me to tell the beta list?"},
 {n:{ar:'ثلاث نقاط',en:'Three bullets'},free:1,o:"- Move the launch by a week\n- Docs aren't ready and Sara is out until the 14th\n- The demo still crashes sometimes"}
];

