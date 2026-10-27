# Starter Kit — Roblox (قبل حصة 17:00)

هادا هو القاعدة اللي خدامة مع **أي نوع لعبة** (Obby، Tycoon، Simulator...). ملي تختار النوع مع 17:00، غادي نزيدو غير كود النوع — هادشي ما غاديش يتعاود.

## شنو كاين هنا

| الملف | فين كيتحط في Studio | شنو كيدير |
|---|---|---|
| `PlayerData.server.lua` | ServerScriptService (Script) | كيحفظ فلوس كل لاعب (Cash) والانتصارات (Wins) وكيعاود يحملهم ملي يدخل — الحفظ هو أصعب جزء للمبتدئين، وهنا واجد |
| `GamepassShop.server.lua` | ServerScriptService (Script) | كيدير الشراء ديال الـ gamepasses (الربح) وكيعاود يعطيهم ملي اللاعب يرجع |
| `Gamepasses.lua` | ReplicatedStorage (ModuleScript) | **الملف الوحيد اللي غادي تبدل فيه:** ملي تصايب gamepasses في موقع Roblox، كتحط الـ IDs ديالهم هنا |

## التركيب (5 دقايق)

1. حل Roblox Studio → مشروع جديد (Baseplate).
2. في الـ Explorer: كليك يمين على **ServerScriptService** → Insert Object → **Script** → سميه `PlayerData` → مسح اللي فيه والصق محتوى `PlayerData.server.lua`.
3. نفس الشي: Script جديد سميه `GamepassShop` → الصق `GamepassShop.server.lua`.
4. كليك يمين على **ReplicatedStorage** → Insert Object → **ModuleScript** → سميه `Gamepasses` → الصق `Gamepasses.lua`.
5. **مهم:** باش الحفظ يخدم في التجربة — Game Settings → Security → فعّل **Enable Studio Access to API Services**.
6. ضغط Play وجرب: دخل، خرج، عاود دخل — الفلوس خاصها تبقى.

## شنو باقي لحصة 17:00

- اختيار النوع (Obby / Tycoon / Simulator).
- كود النوع نفسو (المراحل، المتجر، التأثيرات).
- ملء الـ gamepass IDs الحقيقية في `Gamepasses.lua` من بعد ما تصايبهم في الموقع.

هاد القاعدة ما كتحتاج حتى تبديل ملي يتختار النوع.
