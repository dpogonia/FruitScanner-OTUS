**Русский** | [English](README.en.md)

# Fruit Scanner

Распознавание фруктов и правка лица. Учебный проект OTUS.

## Что умеет приложение

Вкладка «Фрукты» узнаёт яблоко, авокадо, банан, вишню, киви, манго, апельсин, ананас, клубнику и арбуз. Снимок можно взять из фото, с камеры или из AR. Если модель уверена, на экране название и процент.

Вкладка «Редактор» находит лицо на снимке и деформирует его.

## Стек

SwiftUI, Vision, CoreML, ARKit, AVFoundation.

## Запуск

```bash
git clone https://github.com/dpogonia/FruitScanner-OTUS.git
cd FruitScanner-OTUS
open MLAppOTUS.xcodeproj
```

Запустите схему **MLAppOTUS** на симуляторе iPhone. Камера и AR работают на устройстве.

## Автор

[Dmitrii Pogonia](https://github.com/dpogonia)
