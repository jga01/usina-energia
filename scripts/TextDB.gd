# File: scripts/TextDB.gd
# Autoload this script as "TextDB"
extends Node

# Character Selection Screen
const CS_PLAYER_TURN: String = "Jogador %d, Escolha o Seu Personagem"
const CS_CHARACTER_NAME_LABEL_PLACEHOLDER: String = "Nome do Personagem"
const CS_CHARACTER_DESCRIPTION_LABEL_PLACEHOLDER: String = "Descricao do personagem..."
const CS_SELECTED_INFO_PLAYER_STATUS: String = "J%d: %s | "
const CS_CONFIRM_BUTTON_DEFAULT: String = "Confirmar"
const CS_CONFIRM_NEXT_PLAYER_BUTTON: String = "Confirmar e Proximo Jogador"
const CS_CONFIRM_START_GAME_BUTTON: String = "Confirmar e Iniciar Jogo"
const CS_ALL_CONFIRMED_BUTTON: String = "Todos Confirmados"
const CS_NO_CHARACTERS_AVAILABLE: String = "Nenhum Personagem Disponivel!"
const CS_ERROR_NOT_ENOUGH_CHARS: String = "Erro: Personagens unicos insuficientes para todos os jogadores ou conflitos."
const CS_ERROR_CHARACTER_TAKEN: String = "Erro: %s pode ja estar escolhido. Tente outro."
const CS_PLAYER_LABEL_CHOOSING: String = "Escolhendo..."
const CS_PLAYER_LABEL_YOUR_TURN: String = "[Sua Vez]"
const CS_PLAYER_LABEL_SKIPPED: String = "Pulou?"

# Display Screen (Main Game UI)
const DISPLAY_POWER_GRID_STATUS_TITLE: String = "Status da Rede Eletrica"
const DISPLAY_ENERGY_LEVEL_PERCENT: String = "%d%%"
const DISPLAY_STATUS_WAITING: String = "Aguardando..."
const DISPLAY_STATUS_STABLE: String = "Estavel"
const DISPLAY_STATUS_DANGER_MELTDOWN: String = "PERIGO! Colapso Iminente!"
const DISPLAY_STATUS_WARNING_LOW_POWER: String = "Aviso: Baixa Energia"
const DISPLAY_STATUS_WARNING_HIGH_POWER: String = "Aviso: Alta Energia"
const DISPLAY_STATUS_DANGER_OVERLOAD: String = "PERIGO! Sobrecarga Iminente!"
const DISPLAY_STABILITY_GOAL: String = "Meta de Estabilidade: %ds / %ds (%d%%)"
const DISPLAY_STABILITY_GOAL_SUCCESS: String = "Meta de Estabilidade: %ds / %ds (100%%) - SUCESSO!"
const DISPLAY_STABILITY_GOAL_WAITING: String = "Meta de Estabilidade: Aguardando..."
const DISPLAY_STABILITY_GOAL_FINAL_STATUS_PREFIX: String = "Status Final: "
const DISPLAY_GAME_RESETTING: String = "Reiniciando Jogo..."
const DISPLAY_INDIVIDUAL_WIN_TEXT: String = "Vitoria Individual: Jogador %d"
const DISPLAY_GRID_SHUTDOWN_TEXT: String = "Desligamento da Rede"
const DISPLAY_GRID_MELTDOWN_TEXT: String = "Colapso da Rede"

# Player Indicator / Player Actions
const PI_STASH_LABEL: String = "REDIRECIONADO:"
const PI_GENERATE_BUTTON: String = "GERAR"
const PI_STABILIZE_BUTTON: String = "Estabilizar"
const PI_EMERGENCY_BUTTON: String = "EMERGENCIA"
const PI_STEAL_BUTTON: String = "REDIRECIONAR"
const PI_STATUS_LABEL_PREFIX: String = "Status: "
const PI_ELIMINATED_TEXT_SUFFIX: String = " (ELIMINADO)"
const PI_BUTTON_ELIMINATED_TEXT: String = "---"
const PI_STASH_TARGET_UNKNOWN: String = "??"

# Player Action Feedback Statuses (used by GameManager, displayed by PlayerIndicator)
const STATUS_ELECTROCUTED: String = "ELETROCUTADO!"
const STATUS_STABILIZED: String = "Estabilizado!"
const STATUS_STABILIZE_CD: String = "Estabilizar Recarga"
const STATUS_STEAL_CD: String = "Redirecionar Recarga"
const STATUS_LOW_GRID: String = "Rede Baixa!"
const STATUS_STOLE_AMOUNT: String = "Redirecionou %.1f"
const STATUS_EMERGENCY_CD: String = "Emergencia Recarga"
const STATUS_BOOST_USED: String = "Impulso Usado!"
const STATUS_COOLANT_USED: String = "Refrigerador Usado!"
const STATUS_MISUSED: String = "Mal Utilizado!"
const STATUS_UNKNOWN_CMD: String = "Comando Desconhecido"

# Events
const EVENT_UNKNOWN_ALERT: String = "Evento Desconhecido"
const EVENT_SURGE_ALERT: String = "AVISO: Pico de Demanda! (restam %ds)"
const EVENT_EFFICIENCY_ALERT: String = "AVISO: Campanha de Eficiencia! (restam %ds)"

# Game Over Screen
const GO_TITLE_GAME_OVER_DEFAULT: String = "FIM DE JOGO"
const GO_OUTCOME_MESSAGE_DEFAULT_PREFIX: String = "Resultado: "
const GO_OUTCOME_UNKNOWN_NO_DATA: String = "Desconhecido (Nenhum dado recebido ou PlayerProfiles ausente)"
const GO_PLAY_AGAIN_BUTTON: String = "Jogar Novamente"
const GO_MAIN_MENU_BUTTON: String = "Menu Principal"

const GO_TITLE_COOP_WIN: String = "VITORIA COOPERATIVA!"
const GO_MSG_COOP_WIN: String = "VITORIA!\n\nA rede eletrica esta estavel gracas ao seu esforco cooperativo!"
const GO_TITLE_SHUTDOWN: String = "DESLIGAMENTO DA REDE"
const GO_MSG_SHUTDOWN: String = "DERROTA!\n\nA rede sofreu um desligamento critico devido a baixa energia."
const GO_TITLE_INDIVIDUAL_WIN_PLAYER: String = "%s VENCE!"
const GO_TITLE_INDIVIDUAL_WIN_UNKNOWN: String = "VITORIA INDIVIDUAL"
const GO_MSG_INDIVIDUAL_WIN_PLAYER: String = "VITORIA INDIVIDUAL!\n\n%s acumulou poder pessoal suficiente para dominar!"
const GO_MSG_INDIVIDUAL_WIN_UNKNOWN: String = "Vitoria individual por um jogador desconhecido."
const GO_TITLE_ALL_ELIMINATED: String = "TODOS ELIMINADOS"
const GO_MSG_ALL_ELIMINATED: String = "FALHA TOTAL!\n\nTodos os operadores foram eletrocutados. A instalacao esta condenada!"
const GO_TITLE_LAST_PLAYER_STANDING: String = "%s SOBREVIVE!"
const GO_TITLE_LAST_PLAYER_STANDING_UNKNOWN: String = "ULTIMO SOBREVIVENTE"
const GO_MSG_LAST_PLAYER_STANDING: String = "SOBREVIVENTE!\n\n%s e o ultimo operador de pe em meio ao caos!"
const GO_MSG_LAST_PLAYER_STANDING_UNKNOWN: String = "Um operador sobreviveu, mas sua identidade e desconhecida."
const GO_MSG_CONCLUDED_REASON_PREFIX: String = "O jogo terminou. Motivo: %s"


# Main Menu
const MAIN_MENU_START_BUTTON_TEXT: String = "Iniciar"
const MAIN_MENU_STATUS_READY: String = "Pronto para Iniciar Jogo Local."
const MAIN_MENU_STATUS_UDP_ERROR_AUTOLOAD: String = "Erro: Falha ao carregar UdpManager (Autoload)!"
const MAIN_MENU_STATUS_UDP_ERROR_LISTENER: String = "Erro: Falha ao iniciar Ouvinte UDP!"
const MAIN_MENU_IP_LABEL_PREFIX: String = "IP do Ouvinte: %s (Porta: %d)"
const MAIN_MENU_IP_LABEL_ERROR: String = "IP do Ouvinte: Erro"
const MAIN_MENU_IP_LABEL_UNKNOWN_IP: String = "Desconhecido"
const MAIN_MENU_LOADING_CHAR_SELECT: String = "Carregando selecao de personagens..."
const MAIN_MENU_STATUS_UDP_NOT_ACTIVE: String = "Erro: Ouvinte UDP nao esta ativo."


# Generic / Shared
const GENERIC_PLAYER_LABEL_FORMAT: String = "Jogador %d"
