shader_type canvas_item;

// Убрали hint_screen_texture, теперь работаем напрямую с текстурой контейнера
uniform float noise_amount : hint_range(0.0, 1.0) = 0.15; // Чуть больше шума
uniform float contrast : hint_range(0.0, 5.0) = 2.5; 
uniform float brightness : hint_range(-1.0, 1.0) = -0.05; // Чуть затемним фон

// Генератор шума
float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453123);
}

void fragment() {
	// ВАЖНОЕ ИЗМЕНЕНИЕ: Используем TEXTURE и UV вместо screen_texture и SCREEN_UV
	vec4 color = texture(TEXTURE, UV);
	
	// 1. Переводим в ЧБ
	float gray = dot(color.rgb, vec3(0.299, 0.587, 0.114));
	
	// 2. Контраст (формула изменена для сохранения черного)
	// Если пиксель черный (0), он останется черным. Если чуть серый - станет ярче.
	gray = pow(gray, 1.5) * contrast; // pow добавляет глубину черному цвету
	
	// 3. Яркость
	gray += brightness;
	
	// 4. Шум
	float noise = random(UV + vec2(TIME * 20.0, 0.0));
	// Шум накладываем хитро: на черном фоне его меньше, на сером больше
	gray += (noise - 0.5) * noise_amount;
	
	// 5. Сканлайны (полосы)
	float scanline = sin(UV.y * 400.0 + TIME * 10.0) * 0.02;
	gray -= scanline;
	
	// Жестко обрезаем, чтобы не уходить в минус или пересвет
	gray = clamp(gray, 0.0, 1.0);
	
	// Зеленоватый оттенок для реализма (можно убрать, сделав vec3(gray))
	// Для Панциря ч/б стандарт, поэтому оставим ЧБ:
	COLOR = vec4(gray, gray, gray, 1.0);
}