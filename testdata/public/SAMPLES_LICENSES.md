# Лицензии публичных образцов

Пакеты рядом с этим файлом собраны из чужих IFC. Ниже только то, что написано в лицензии и в самом файле. Формат `.fbvpkg` не менялся.

Три файла `Building-*.ifc` лежат в одном репозитории и покрыты одним файлом `LICENSE`. Выводы по тексту лицензии для них общие. У `Borehole-1.ifc` своё уведомление внутри файла и отдельно лицензия репозитория.

## Creative Commons Attribution 4.0 International

Так названа лицензия в файле `LICENSE` репозитория [buildingSMART/Certification-datasets](https://github.com/buildingSMART/Certification-datasets), коммит `80d976a9b193a26a8e928c3e79bff67af1de68a8`. Текст этого файла:

> (C) buildingSMART International Ltd.
>
> This work is licensed under the Creative Commons Attribution 4.0 International License.
> More info and a link to the full license text is available on http://creativecommons.org/licenses/by/4.0/
>
> Read the full license on https://creativecommons.org/licenses/by/4.0/legalcode.txt

В `README.md` того же коммита строка: `Copyright © buildingSMART International Ltd.`

Текст лицензии, по ссылке из `LICENSE`: [Attribution 4.0 International legal code](https://creativecommons.org/licenses/by/4.0/legalcode.txt). Абзац «Using Creative Commons Public Licenses» прямо говорит, что соображения для публики не входят в лицензию. Ниже выводы только из разделов 2 и 3.

Коммерческое использование. Раздел 2(a)(1) даёт всемирную безвозмездную лицензию воспроизводить и распространять (`Share`) материал целиком или частично и создавать, воспроизводить и распространять переработанный материал (`Adapted Material`). Раздел 3 ставит условием указание авторства. Некоммерческого ограничения в этих разделах нет.

Можно ли вложить образец в APK. Раздел 2(a)(1)(b) разрешает переработку и её распространение, раздел 2(a)(4) — в любом носителе и формате, известном сейчас или позже. Пакет `.fbvpkg` внутри APK — такое распространение переработанного материала. Раздел 3(a)(4): лицензия, на которой вы отдаёте свою переработку, не должна мешать получателю выполнить условия этой публичной лицензии.

Какое указание авторства и где. Если материал распространяется, в том числе в изменённом виде, раздел 3(a)(1) требует сохранить то, что приложил лицензиар: кто создатель и кого он просит указать; уведомление об авторском праве; уведомление об этой лицензии; уведомление об отказе от гарантий, если оно приложено; по разумной возможности ссылку на материал. Нужно отметить, что материал изменён, и указать, что он под этой лицензией, приложив её текст или ссылку. Раздел 3(a)(2): сделать это можно любым разумным для носителя способом. Пример в тексте лицензии — ссылка на страницу, где эти сведения собраны. Лицензия не называет экран «О программе». Такой экран подходит, если на нём есть перечисленные сведения.

В файле `LICENSE` назван правообладатель buildingSMART International Ltd. и даны ссылки на лицензию. Отдельного текста отказа от гарантий в этом файле нет.

## Building-Architecture.ifc

Исходный файл: [Building-Architecture.ifc](https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Architecture.ifc), каталог `IFC 2.3.0.1 (IFC 2x3 TC1)/Simple-Scene`, коммит `80d976a9b193a26a8e928c3e79bff67af1de68a8`. SHA-256 файла `c4db65ba847f6b369a95d6c54fa11f4750cbe6d59f021934e8923d8d578e5885`.

Автор. В `LICENSE` и `README` назван buildingSMART International Ltd. Поле `author` в `FILE_NAME` этого IFC пустое. Имя человека лицензия не указывает.

Лицензия: Creative Commons Attribution 4.0 International. Текст: [legalcode.txt](https://creativecommons.org/licenses/by/4.0/legalcode.txt). Выводы по коммерческому использованию, вложению в APK и месту указания авторства — в разделе выше.

Строка для указания авторства:

`Building-Architecture.ifc © buildingSMART International Ltd. Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/legalcode.txt. Источник: https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Architecture.ifc. Building-Architecture.fbvpkg — изменённая форма: триангуляция ifcopenshell-occt, конвертер fbvconv 0.1.0.`

## Building-Structural.ifc

Исходный файл: [Building-Structural.ifc](https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Structural.ifc), тот же каталог и коммит. SHA-256 `25c09f1ea35dbf51e88b8829c423b9ce13a8264e69c620e932859772937aa25b`.

Автор. Тот же файл `LICENSE`: buildingSMART International Ltd. Поле `author` в `FILE_NAME` пустое.

Лицензия: Creative Commons Attribution 4.0 International, [legalcode.txt](https://creativecommons.org/licenses/by/4.0/legalcode.txt). Выводы — в общем разделе CC BY 4.0 выше.

Строка для указания авторства:

`Building-Structural.ifc © buildingSMART International Ltd. Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/legalcode.txt. Источник: https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Structural.ifc. Building-Structural.fbvpkg — изменённая форма: триангуляция ifcopenshell-occt, конвертер fbvconv 0.1.0.`

## Building-Hvac.ifc

Исходный файл: [Building-Hvac.ifc](https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Hvac.ifc), тот же каталог и коммит. SHA-256 `f39478ce12ae2029eed8b565551412a3a4b518d10a8b501bc5e9c2a8a6d78bdb`.

Автор. Тот же файл `LICENSE`: buildingSMART International Ltd. Поле `author` в `FILE_NAME` пустое.

Лицензия: Creative Commons Attribution 4.0 International, [legalcode.txt](https://creativecommons.org/licenses/by/4.0/legalcode.txt). Выводы — в общем разделе CC BY 4.0 выше.

Строка для указания авторства:

`Building-Hvac.ifc © buildingSMART International Ltd. Creative Commons Attribution 4.0 International, https://creativecommons.org/licenses/by/4.0/legalcode.txt. Источник: https://raw.githubusercontent.com/buildingSMART/Certification-datasets/80d976a9b193a26a8e928c3e79bff67af1de68a8/IFC%202.3.0.1%20(IFC%202x3%20TC1)/Simple-Scene/Building-Hvac.ifc. Building-Hvac.fbvpkg — изменённая форма: триангуляция ifcopenshell-occt, конвертер fbvconv 0.1.0.`

## Borehole-1.ifc

Исходный файл: [Borehole-1.ifc](https://raw.githubusercontent.com/bSI-InfraRoom/IFC-infra-unit-test/bc13603cc4899084edbf9f1d9151443a7fb4cf0e/Borehole-1/Borehole-1.ifc), репозиторий [bSI-InfraRoom/IFC-infra-unit-test](https://github.com/bSI-InfraRoom/IFC-infra-unit-test), коммит `bc13603cc4899084edbf9f1d9151443a7fb4cf0e`. SHA-256 `f4ef5549c3e773048d0178f88c50ca167e146188f8c5e2565fb15934ebceec50`.

Автор. В `FILE_NAME` записано `author` `JonMirtschin`, `organization` `Geometry Gym`. В описании `IFCPROJECT` «FG6280» записана строка (знак © в файле закодирован как `\X2\00A9\X0\`):

`http://creativecommons.org/licenses/by/3.0/au/ © State of Queensland(Department of Transport and Main Roads) 2016`

Название в том же объекте: `Gold Coast Light Rail(GCLR) Stage 2`.

Лицензия, названная в самом IFC: Creative Commons Attribution 3.0 Australia. Ссылка из файла: <http://creativecommons.org/licenses/by/3.0/au/>. Текст лицензии: [Attribution 3.0 Australia legal code](https://creativecommons.org/licenses/by/3.0/au/legalcode).

Коммерческое использование. Пункт 3A даёт всемирную безвозмездную лицензию на срок авторского права: воспроизводить произведение, включать его в сборник, создавать и воспроизводить производные произведения, распространять и публично исполнять произведение, производное произведение или сборник. Некоммерческого ограничения в пункте 3A нет.

Можно ли вложить образец в APK. Пункты 3A(d), 3A(e) и 3B разрешают производное произведение в любом носителе и формате. Пакет `.fbvpkg` — производное произведение: файл изменён конвертацией. Пункт 4A(g) говорит о неизменённом произведении внутри сборника и не переносит лицензию на остальной сборник. Для производного произведения при распространении действует пункт 4B.

Какое указание авторства и где. Пункт 4B(a) требует сохранить уведомления об авторском праве. Пункт 4B(b): способом, разумным для носителя, указать имя автора или псевдоним и тех, кого автор или лицензиар просит указать (в тексте это attribution parties, пример — copyright notice); название произведения, если оно есть; по разумной возможности ссылку, которую лицензиар связал с уведомлением об авторском праве или с лицензией. Пункт 4B(c): ясно отметить, что изменения внесены. Пункт 4B(d): в производном произведении или сборнике такое указание должно быть как минимум среди указаний других авторов и не менее заметным, чем они. Лицензия не называет экран «О программе». Он подходит, если указание стоит среди прочих credits и так же заметно. Пункт 4B(f) запрещает этим указанием утверждать связь, спонсорство или одобрение со стороны автора или лицензиара без их отдельного письменного разрешения.

Отдельно репозиторий в коммите `bc13603cc4899084edbf9f1d9151443a7fb4cf0e` содержит [LICENSE.txt](https://raw.githubusercontent.com/bSI-InfraRoom/IFC-infra-unit-test/bc13603cc4899084edbf9f1d9151443a7fb4cf0e/LICENSE.txt):

> (C) original authors
>
> This work is licensed under the Creative Commons Attribution 4.0 International License.
> More info and a link to the full license text is available on http://creativecommons.org/licenses/by/4.0/

Имя лицензии: Creative Commons Attribution 4.0 International. Ссылка, которую даёт этот файл: <http://creativecommons.org/licenses/by/4.0/>. Текст, который читался для выводов: [legalcode.txt](https://creativecommons.org/licenses/by/4.0/legalcode.txt). Выводы те же, что в общем разделе CC BY 4.0: раздел 2(a)(1) разрешает воспроизведение и переработку, раздел 3 требует указание авторства, некоммерческого ограничения в этих разделах нет. В `LICENSE.txt` автор назван только словами `original authors`.

Строка для указания авторства:

`Borehole-1.ifc, «FG6280», Gold Coast Light Rail (GCLR) Stage 2. © State of Queensland (Department of Transport and Main Roads) 2016. Creative Commons Attribution 3.0 Australia, https://creativecommons.org/licenses/by/3.0/au/legalcode. FILE_NAME: JonMirtschin, Geometry Gym. Репозиторий дополнительно: (C) original authors, Creative Commons Attribution 4.0 International, http://creativecommons.org/licenses/by/4.0/, коммит bc13603cc4899084edbf9f1d9151443a7fb4cf0e. Borehole-1.fbvpkg — изменённая форма: схема IFC4X3_RC3, меш analytic-extrusion-v1, конвертер fbvconv 0.1.0.`

## Как собраны пакеты

Сборка локальная, пресет `linux-gcc-ifcopenshell` (Release): Open CASCADE 7.8.1 и IfcOpenShell 0.8.5, схемы 2x3, 4 и 4x3_add2. Команда для трёх файлов Certification datasets: `fbvconv <файл>.ifc -o <файл>.fbvpkg --mesher ifcopenshell --max-threads 2`. В манифесте мешер `ifcopenshell-occt`. `pkg_validate` вернул 0.

`Borehole-1.ifc` передан тому же `fbvconv` с `--mesher ifcopenshell`. В журнале: `IfcOpenShell could not parse the file (unsupported schema or syntax). The analytic mesher will run.` Схема файла `IFC4X3_RC3` в этот набор схем не входит. Меш записан запасным путём `analytic-extrusion-v1`: 5 элементов с телом, у `IfcBorehole` представления нет. `pkg_validate` вернул 0.

Прежние `testdata/sample_wall.fbvpkg` и `testdata/sample_model` этим же `pkg_validate` открываются.
