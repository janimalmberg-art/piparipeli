;==========================================================
; C64 PIPARI LEIPOMO - ACME ASSEMBLER
; Liikutus: W,A,S,D
; Toiminta: RETURN / SPACE
; Uudelleenkäynnistys: L
;==========================================================

!cpu 6502
!to "leipomo.prg", cbm

;--- VAKIOT ---
VIC_SPR_X       = $d000
VIC_SPR_Y       = $d001
VIC_SPR_MSB     = $d010
VIC_CTRL1       = $d011
VIC_RASTER      = $d012
VIC_SPR_ENA     = $d015
VIC_CTRL2       = $d016
VIC_SPR_EXP_Y   = $d017
VIC_MEM         = $d018
VIC_SPR_EXP_X   = $d01d
VIC_SPR_COL     = $d027
VIC_BG_COL      = $d021
VIC_BORDER      = $d020

SID_RAND        = $d41b ; Satunnaisluku

SCREEN_RAM      = $0400
COLOR_RAM       = $d800
SPRITE_PTR      = SCREEN_RAM + $3f8

;--- PELIN MUUTTUJAT (Zero Page) ---
PLAYER_X        = $fb
PLAYER_Y        = $fc
GAME_STATE      = $fd ; 0=Start, 1=Play, 2=MiniGame, 3=Win
CYCLE_PHASE     = $fe ; 0=Mix, 1=Roll, 2=Bake, 3=Sell

;--- MUISTIPAIKAT ---
MONEY_LO        = $2000
MONEY_HI        = $2001
TEMP            = $2002
FRAME_COUNT     = $2003
OVEN_TIMER      = $2004
CURSOR_POS      = $2005 ; Minipeli valinta
REQ_COOKIES     = $2006 ; Asiakkaan toive

;--- STARTUP HEADER ---
* = $0801
!byte $0b, $08, $ef, $00, $9e, $32, $30, $36, $34, $00, $00, $00
* = $0810

;==========================================================
; INITIALIZATION
;==========================================================
Init:
    sei
    lda #$00
    sta VIC_BORDER
    lda #$0b        ; Tummanharmaa tausta
    sta VIC_BG_COL
    
    jsr ClearScreen
    jsr InitSprites
    jsr DrawBakery  ; Piirrä keittiö (PETSCII)

    lda #0
    sta MONEY_LO
    sta MONEY_HI
    sta CYCLE_PHASE
    sta FRAME_COUNT
    
    lda #1
    sta GAME_STATE  ; Aloita suoraan pelitilasta

    ; Aseta ukko keskelle
    lda #160
    sta PLAYER_X
    lda #150
    sta PLAYER_Y

GameLoop:
    ; 1. Odota rasteria (hidastus / synkka)
    lda #$ff
WaitRaster:
    cmp VIC_RASTER
    bne WaitRaster

    inc FRAME_COUNT

    ; 2. Tarkista globaalit näppäimet (L = Restart)
    jsr CheckRestart

    ; 3. Haarauta pelitilan mukaan
    lda GAME_STATE
    cmp #1
    beq State_Kitchen
    cmp #2
    beq State_Rolling
    cmp #3
    beq State_GameOver
    jmp GameLoop

;==========================================================
; TILA 1: KEITTIÖ (Pääpeli)
;==========================================================
State_Kitchen:
    jsr CheckInputWASD      ; Lue W,A,S,D ja päivitä X/Y
    jsr UpdatePlayerSprite  ; Siirrä spriteä
    jsr UpdateCarrySprite   ; Päivitä taikina/piparit ukon mukana
    jsr CheckStations       ; Tarkista ollaanko pisteillä
    jsr DrawUI              ; Päivitä rahatilanne
    
    ; Voittotarkistus (1500 mk = $05DC)
    lda MONEY_HI
    cmp #$05
    bcc .notwon
    bne .won        ; Jos > 5, voitto
    lda MONEY_LO
    cmp #$dc
    bcc .notwon
.won:
    lda #3
    sta GAME_STATE
    jsr DrawWinScreen
.notwon:
    jmp GameLoop

;==========================================================
; TILA 2: KAULINTA (Minipeli)
;==========================================================
State_Rolling:
    ; Näytä iso taikinalevy ja kursori
    ; Käytetään samoja nappeja valintaan
    jsr RollingMiniGameLogic
    jmp GameLoop

;==========================================================
; TILA 3: GAME OVER
;==========================================================
State_GameOver:
    ; Odotetaan vain L-kirjainta (CheckRestart hoitaa)
    jmp GameLoop


;==========================================================
; ALIRUTIINIT: LIIKKUMINEN & SYÖTE
;==========================================================
CheckInputWASD:
    ; W (Ylös)
    lda #$fd        ; Row 1
    sta $dc00
    lda $dc01
    and #$02        ; Col 1 (W)
    bne .check_s
    dec PLAYER_Y
    dec PLAYER_Y    ; Nopeampi liike

.check_s:
    ; S (Alas)
    lda #$df        ; Row 5
    sta $dc00
    lda $dc01
    and #$20        ; Col 5 (S)
    bne .check_a
    inc PLAYER_Y
    inc PLAYER_Y

.check_a:
    ; A (Vasen)
    lda #$fd        ; Row 1
    sta $dc00
    lda $dc01
    and #$04        ; Col 2 (A)
    bne .check_d
    dec PLAYER_X
    dec PLAYER_X

.check_d:
    ; D (Oikea)
    lda #$fb        ; Row 2
    sta $dc00
    lda $dc01
    and #$04        ; Col 2 (D)
    bne .check_action
    inc PLAYER_X
    inc PLAYER_X

.check_action:
    ; Return tai Space toiminnaksi
    lda #$fe        ; Row 0 (Return on bit 1)
    sta $dc00
    lda $dc01
    and #$02
    beq .action_pressed
    
    lda #$7f        ; Space check (Row 7, Col 4)
    sta $dc00
    lda $dc01
    and #$10
    beq .action_pressed
    rts

.action_pressed:
    jmp HandleAction

CheckRestart:
    ; L-kirjain (Row 5, Col 2) -> $DF, bit $04
    lda #$df
    sta $dc00
    lda $dc01
    and #$04
    bne .no_restart
    jmp Init    ; Hyppää alkuun
.no_restart:
    rts

;==========================================================
; ALIRUTIINIT: PELILOGIIKKA JA PISTEET
;==========================================================

HandleAction:
    ; Estetään liian nopea rämpytys
    lda FRAME_COUNT
    and #$0f
    bne .exit

    ; Tarkista mikä vaihe menossa ja missä pelaaja on
    ; Sijainnit (Hardcoded zones based on DrawBakery)
    
    ; 1. MIXER (Ylhäällä vasemmalla) - X<100, Y<100
    lda PLAYER_X
    cmp #100
    bcs .check_table
    lda PLAYER_Y
    cmp #100
    bcs .exit
    
    lda CYCLE_PHASE
    cmp #0          ; Odottaa taikinan tekoa
    bne .exit
    inc CYCLE_PHASE ; -> 1 (Taikina valmis)
    jsr SetStatusText
    rts

.check_table:
    ; 2. TABLE (Ylhäällä oikealla) - X>200, Y<100
    lda PLAYER_X
    cmp #200
    bcc .check_oven
    lda PLAYER_Y
    cmp #100
    bcs .exit
    
    lda CYCLE_PHASE
    cmp #1          ; Onko taikina mukana?
    bne .exit
    ; Mene minipeliin
    lda #2
    sta GAME_STATE
    jsr InitMiniGame
    rts

.check_oven:
    ; 3. OVEN (Alhaalla oikealla) - X>200, Y>180
    lda PLAYER_X
    cmp #200
    bcc .check_reg
    lda PLAYER_Y
    cmp #180
    bcc .exit
    
    lda CYCLE_PHASE
    cmp #3          ; Onko raakoja pipareita?
    beq .start_bake
    
    ; Jos uuni on valmis (OVEN_TIMER = 0 ja vaihe paistossa)
    ; Tässä yksinkertaistus: Jos paistettu, ota pois
    rts

.start_bake:
    lda #4
    sta CYCLE_PHASE ; Paistetaan
    lda #100        ; Ajastin
    sta OVEN_TIMER
    rts

.check_reg:
    ; 4. REGISTER (Alhaalla vasemmalla) - X<100, Y>180
    lda PLAYER_X
    cmp #100
    bcs .exit
    lda PLAYER_Y
    cmp #180
    bcc .exit
    
    lda CYCLE_PHASE
    cmp #5          ; Onko valmiita pipareita?
    bne .exit
    
    ; MYYNTI TAPAHTUU!
    jsr AddMoney
    lda #0
    sta CYCLE_PHASE ; Alusta kierto
    jsr SetStatusText
    
.exit:
    rts

;--- Logiikka uunin päivitykselle ---
CheckStations:
    lda CYCLE_PHASE
    cmp #4          ; Paistaminen käynnissä?
    bne .not_baking
    
    dec OVEN_TIMER
    bne .flash_oven
    
    ; Valmis!
    lda #5
    sta CYCLE_PHASE
    lda #$05        ; Vihreä valo spriteen
    sta VIC_SPR_COL+1
    rts

.flash_oven:
    ; Välkytä uunin väriä taustalla tai spritessä
    lda FRAME_COUNT
    and #$04
    bne .col1
    lda #$02 ; Pun
    jmp .setc
.col1:
    lda #$07 ; Kelt
.setc:
    sta VIC_SPR_COL+1
.not_baking:
    rts

;--- Rahojen lisäys (80 mk) ---
AddMoney:
    sed             ; Decimal mode päälle
    clc
    lda MONEY_LO
    adc #$80
    sta MONEY_LO
    lda MONEY_HI
    adc #$00
    sta MONEY_HI
    cld             ; Decimal mode pois
    rts

;==========================================================
; MINIPELI: TAIKINAN KAULINTA JA MUOTIT
;==========================================================
InitMiniGame:
    jsr ClearScreen
    
    ; Generoi "Asiakas haluaa"
    lda SID_RAND
    and #$03
    sta REQ_COOKIES ; 0-3 muottityyppi
    
    ; Tulosta teksti
    ldx #0
.msg_loop:
    lda txt_roll,x
    beq .done_msg
    sta SCREEN_RAM+2*40+2,x
    inx
    jmp .msg_loop
.done_msg:

    ; Piirrä iso "Taikina" merkeillä ruudun keskelle
    ldx #10
.dl1:
    ldy #10
.dl2:
    lda #$a0        ; Käänteinen välilyönti (neliö)
    sta SCREEN_RAM+10*40+10,x
    iny
    dex
    bne .dl1
    
    lda #0
    sta CURSOR_POS
    rts

RollingMiniGameLogic:
    ; Lue 1-4 näppäimet piparimuoteiksi
    ; 1=$31, 2=$32 ...
    jsr GetChar
    cmp #0
    beq .no_key
    
    ; Tarkista painoiko oikeaa numeroa (simuloidaan hiiren valinta)
    ; Asiakas haluaa tyyppiä REQ_COOKIES (0..3) -> Näppäin '1'.. '4'
    sec
    sbc #$31        ; Muuta ASCII '1' -> 0
    cmp REQ_COOKIES
    bne .wrong
    
    ; Oikea valinta!
    lda #3          ; Vaihe: Raaka pipari
    sta CYCLE_PHASE
    lda #1          ; Takaisin keittiöön
    sta GAME_STATE
    jsr DrawBakery
    rts

.wrong:
    ; Väärä valinta, väläytä reunusta
    inc VIC_BORDER
.no_key:
    rts

GetChar:
    jsr $ffe4       ; KERNAL GETIN
    rts

;==========================================================
; GRAFIIKKA JA SPRITET
;==========================================================
InitSprites:
    lda #$ff
    sta VIC_SPR_ENA ; Kaikki päälle (käytetään vain 0 ja 1)
    
    ; Sprite 0: Leipuri
    lda #192        ; Osoite $3000 / $40 = 192
    sta SPRITE_PTR
    lda #1          ; Valkoinen
    sta VIC_SPR_COL
    
    ; Sprite 1: Kärry/Taikina
    lda #193
    sta SPRITE_PTR+1
    lda #9          ; Ruskea
    sta VIC_SPR_COL+1
    
    rts

UpdatePlayerSprite:
    ; X-koordinaatti (Yksinkertaistettu, ei MSB tukea tässä demossa)
    lda PLAYER_X
    asl             ; Kerroin (skaalaus jos tarpeen) - tässä suoraan
    lsr
    sta VIC_SPR_X
    
    lda PLAYER_Y
    sta VIC_SPR_Y
    rts

UpdateCarrySprite:
    ; Kärry seuraa pelaajaa, mutta visuaalinen tila vaihtuu
    lda PLAYER_X
    clc
    adc #12
    sta VIC_SPR_X+2
    
    lda PLAYER_Y
    clc
    adc #5
    sta VIC_SPR_Y+2
    
    ; Vaihda spriten ulkonäkö vaiheen mukaan
    ldx CYCLE_PHASE
    ; 0: Tyhjä (piilota?) -> Ei, näytä tyhjä kärry
    ; 1: Taikina
    ; 3: Raaka
    ; 5: Kypsä
    rts

DrawBakery:
    jsr ClearScreen
    
    ; Piirrä "Pisteet"
    ldx #0
.l1:
    lda txt_mixer,x
    beq .l2
    sta SCREEN_RAM+2*40+2,x  ; Mixer ylös vasen
    inx
    jmp .l1
.l2:
    ldx #0
.l3:
    lda txt_table,x
    beq .l4
    sta SCREEN_RAM+2*40+30,x ; Pöytä ylös oikea
    inx
    jmp .l3
.l4:
    ldx #0
.l5:
    lda txt_oven,x
    beq .l6
    sta SCREEN_RAM+20*40+30,x ; Uuni alas oikea
    inx
    jmp .l5
.l6:
    ldx #0
.l7:
    lda txt_reg,x
    beq .l8
    sta SCREEN_RAM+20*40+2,x  ; Kassa alas vasen
    inx
    jmp .l7
.l8:
    rts

DrawUI:
    ; Piirrä rahat ylös keskelle
    lda #$24 ; '$'
    sta SCREEN_RAM+1
    
    ; Näytä Hexana (yksinkertaistus) tai BCD
    lda MONEY_HI
    jsr PrintHex
    sta SCREEN_RAM+2
    stx SCREEN_RAM+3
    
    lda MONEY_LO
    jsr PrintHex
    sta SCREEN_RAM+4
    stx SCREEN_RAM+5
    rts

PrintHex:
    ; Muuttaa Akun luvun kahdeksi PETSCII merkiksi (A ja X)
    pha
    lsr
    lsr
    lsr
    lsr
    tax
    lda HexChars,x
    tay ; Y = High nibble char
    pla
    and #$0f
    tax
    lda HexChars,x
    tax ; X = Low nibble char
    tya ; A = High nibble char
    rts

HexChars: !text "0123456789abcdef"

ClearScreen:
    ldx #0
    lda #$20 ; Space
.cs_loop:
    sta SCREEN_RAM,x
    sta SCREEN_RAM+250,x
    sta SCREEN_RAM+500,x
    sta SCREEN_RAM+750,x
    lda #1   ; Väri (valkoinen teksti)
    sta COLOR_RAM,x
    sta COLOR_RAM+250,x
    sta COLOR_RAM+500,x
    sta COLOR_RAM+750,x
    inx
    bne .cs_loop
    rts

SetStatusText:
    ; Voidaan lisätä tekstirivi alareunaan riippuen vaiheesta
    rts

DrawWinScreen:
    jsr ClearScreen
    ldx #0
.w1:
    lda txt_win,x
    beq .wd
    sta SCREEN_RAM+10*40+5,x
    inx
    jmp .w1
.wd:
    rts

;==========================================================
; DATA
;==========================================================

txt_mixer:  !text "TAIKINAKONE",0
txt_table:  !text "LEIVONTAPOYTA",0
txt_oven:   !text "UUNI",0
txt_reg:    !text "KASSA",0
txt_roll:   !text "VALITSE MUOTTI 1-4 (ASIAKAS TOIVOO)",0
txt_win:    !text "PELI LAPAPI! RAHAT KERATTY! L=UUSI",0

;--- SPRITE DATA ($3000 -> 12288) ---
* = $3000
; Sprite 0: Ukko (Yksinkertainen hahmo)
!byte 0,60,0
!byte 0,66,0
!byte 0,129,0
!byte 0,129,0
!byte 0,66,0
!byte 0,60,0
!byte 3,255,192
!byte 4,0,32
!byte 8,0,16
!byte 16,0,8
!byte 16,0,8
!byte 16,0,8
!byte 16,0,8
!byte 31,255,248
!byte 4,0,32
!byte 4,0,32
!byte 4,0,32
!byte 6,0,96
!byte 0,0,0
!byte 0,0,0
!byte 0 ; Padding

; Sprite 1: Kärry / Pelti
* = $3040
!byte 0,0,0
!byte 0,0,0
!byte 0,0,0
!byte 0,0,0
!byte 63,255,252
!byte 32,0,4
!byte 32,36,4
!byte 32,0,4
!byte 32,144,4
!byte 32,0,4
!byte 32,36,4
!byte 32,0,4
!byte 63,255,252
!byte 0,0,0
!byte 2,0,64
!byte 2,0,64
!byte 5,0,160
!byte 0,0,0
!byte 0,0,0
!byte 0,0,0
!byte 0