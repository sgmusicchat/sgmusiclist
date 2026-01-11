<?php
header('Content-Type: application/json');
require_once '../includes/config.php';

// OpenRouter API
$api_key = defined('OPENROUTER_API_KEY') ? OPENROUTER_API_KEY : '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';
$model = 'google/gemini-2.0-flash-001';  // Or 'meta-llama/llama-3.1-8b-instruct:free'; // Free model via OpenRouter
$userInput = $_POST['text'] ?? '';

if (empty(trim($userInput))) {
    echo json_encode(['success' => false, 'message' => 'No input']); 
    exit;
}

// 1. AI Parsing
$prompt = "Context: Singapore Electronic Music events. Extract filters from: \"$userInput\". 
Return JSON ONLY with these exact keys: 
{ \"v\": string|null (venue name), \"g\": string|null (genre), \"p_max\": number|null (max price), \"free\": boolean|null (free events only) }
Examples: 'techno at Zouk' -> {\"v\":\"Zouk\",\"g\":\"techno\",\"p_max\":null,\"free\":null}
'free house events' -> {\"v\":null,\"g\":\"house\",\"p_max\":null,\"free\":true}
'events under 50 dollars' -> {\"v\":null,\"g\":null,\"p_max\":50,\"free\":null}";

$ch = curl_init("https://openrouter.ai/api/v1/chat/completions");
curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode([
    "model" => $model,
    "messages" => [
        [
            "role" => "user",
            "content" => $prompt
        ]
    ],
    "response_format" => ["type" => "json_object"]
]));
curl_setopt($ch, CURLOPT_HTTPHEADER, [
    'Content-Type: application/json',
    'Authorization: Bearer ' . $api_key,
    'HTTP-Referer: ' . ($_SERVER['HTTP_REFERER'] ?? 'http://localhost'), // Optional but recommended
    'X-Title: Singapore Events Search' // Optional but recommended
]);
$response = curl_exec($ch);
$http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
curl_close($ch);

// Check for API errors
if ($http_code !== 200) {
    $error_data = json_decode($response, true);
    $error_msg = $error_data['error']['message'] ?? 'Unknown API error';
    echo json_encode(['success' => false, 'message' => 'OpenRouter API Error: ' . $error_msg, 'debug' => $response]);
    exit;
}

// Validate AI response
$response_data = json_decode($response, true);
if (!isset($response_data['choices'][0]['message']['content'])) {
    echo json_encode(['success' => false, 'message' => 'AI parsing failed', 'debug' => $response]);
    exit;
}

// Parse the JSON content
$ai_text = $response_data['choices'][0]['message']['content'];
// Remove markdown code blocks if present
$ai_text = preg_replace('/```json\s*|\s*```/', '', $ai_text);
$ai_data = json_decode(trim($ai_text), true);

if (json_last_error() !== JSON_ERROR_NONE) {
    echo json_encode(['success' => false, 'message' => 'Invalid AI response format', 'debug' => $ai_text]);
    exit;
}

// 2. SQL Build
try {
    $conditions = [];
    $params = [];

    // Venue filter - case-insensitive partial match
    if (!empty($ai_data['v'])) {
        $conditions[] = "venue_name LIKE :v";
        $params['v'] = "%" . $ai_data['v'] . "%";
    }
    
    // Genre filter - word boundary matching for comma-separated genres
    if (!empty($ai_data['g'])) {
        $conditions[] = "(genres_concat LIKE :g1 OR genres_concat LIKE :g2 OR genres_concat LIKE :g3 OR genres_concat = :g4)";
        $genre = $ai_data['g'];
        $params['g1'] = $genre . ",%";          // Start of list: "techno, house"
        $params['g2'] = "%, " . $genre . ",%";  // Middle: "house, techno, trance"
        $params['g3'] = "%, " . $genre;         // End: "house, techno"
        $params['g4'] = $genre;                 // Only genre: "techno"
    }
    
    // Price filter - events where price_min is within budget
    if (isset($ai_data['p_max']) && is_numeric($ai_data['p_max'])) {
        $conditions[] = "(price_min <= :p_max OR is_free = 1)";
        $params['p_max'] = floatval($ai_data['p_max']);
    }
    
    // Free events filter
    if (isset($ai_data['free']) && $ai_data['free'] === true) {
        $conditions[] = "is_free = 1";
    }

    $where = !empty($conditions) ? "WHERE " . implode(" AND ", $conditions) : "";
    
    $sql = "SELECT event_name, venue_name, event_date, start_time, genres_concat, 
                   price_min, price_max, is_free, ticket_url 
            FROM v_live_events 
            $where 
            ORDER BY event_date ASC 
            LIMIT 20";

    $stmt = $pdo_gold->prepare($sql);
    $stmt->execute($params);
    $results = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        'success' => true, 
        'data' => $results, 
        'filters_applied' => $ai_data,
        'result_count' => count($results)
    ]);
    
} catch (Exception $e) {
    echo json_encode(['success' => false, 'message' => $e->getMessage()]);
}