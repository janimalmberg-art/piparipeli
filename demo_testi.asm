;==========================================================
; C64 JOULUPIPARIPELI - ACME ASSEMBLER
; Tekija: Jani Malmberg 
; Liikutus: W,A,S,D
; Toiminta: RETURN (Enter)
; Aloitus / restart: L
;==========================================================

!cpu 6502
!to "piparipeli.prg", cbm

;--- VAKIOT ---
VIC_SPR_X       = $d000
VIC_SPR_Y       = $d001
VIC_SPR_MSB     = $d010
VIC_RASTER      = $d012
VIC_SPR_ENA     = $d015
VIC_SPR_EXP_Y   = $d017
VIC_MEM         = $d018
VIC_SPR_EXP_X   = $d01d
VIC_SPR_COL     = $d027
VIC_BG_COL      = $d021
VIC_BORDER      = $d020

SID_RAND        = $d41b

SCREEN_RAM      = $0400
COLOR_RAM       = $d800
SPRITE_PTR      = SCREEN_RAM + $3f8

;--- PELIN MUUTTUJAT (Zero Page) ---
PLAYER_X        = $fb
PLAYER_Y        = $fc
GAME_STATE      = $fd 
CYCLE_PHASE     = $fe 

; LISÄÄ NÄMÄ TÄHÄN (Nollasivulle, alle $FF):
TEXT_PTR_LO     = $f9
TEXT_PTR_HI     = $fa

FRAME_COUNT     = $2003


;--- MUISTIPAIKAT ---
MONEY_LO        = $2010
MONEY_HI        = $2011
OVEN_TIMER      = $2012

; Asiakastilaus: montako piparia tyyppia 0..3 viela tarvitaan
ORDER_TGT0      = $2013
ORDER_TGT1      = $2014
ORDER_TGT2      = $2015
ORDER_TGT3      = $2016

CUR_SHAPE       = $2017  ; valittu muotti 0..3
CURSOR_X        = $2018  ; hiirikursorin X
CURSOR_Y        = $2019  ; hiirikursorin Y
MOUSE_BTN_LAST  = $201a  ; 0=ylos, 1=oli alas edellisella framella



;--- STARTUP HEADER (BASIC: 239 SYS2064) ---
* = $0801
!byte $0b, $08, $ef, $00, $9e, $32, $30, $36, $34, $00, $00, $00
* = $0810

;==========================================================
; ALUSTUS
;==========================================================
Init:
    sei
    lda #0
    sta VIC_BORDER
    lda #11         ; tummanharmaa tausta
    sta VIC_BG_COL

    ; ruutu $0400, oletusmerkkisto
    lda #$14
    sta VIC_MEM

    jsr ClearScreen
    
    ; nollaa pelitila ja laskurit
    lda #0
    sta MONEY_LO
    sta MONEY_HI
    sta GAME_STATE
    sta CYCLE_PHASE
    sta FRAME_COUNT
    
    jmp State_Intro

;==========================================================
; PAALOOPPI
;==========================================================
GameLoop:
    ; synkkaus rasteriin (hidastus)
    lda #$ff
WaitRaster:
    cmp VIC_RASTER
    bne WaitRaster

    inc FRAME_COUNT

    ;------------------------------------------
    ; L-nappain: aloitus introssa, restart pelissa
    ;------------------------------------------
    lda #$df
    sta $dc00
    lda $dc01
    and #$04
    bne .no_L_pressed

    ; L painettu
    lda GAME_STATE
    beq .start_game_from_intro   ; 0 = intro

    ; muussa tilassa: restart koko peli
    jmp Init

.start_game_from_intro:
    jmp InitGame

.no_L_pressed:

    ; tilakone
    lda GAME_STATE
    cmp #0
    beq .do_intro
    cmp #1
    beq .do_kitchen
    cmp #2
    beq .do_baking
    jmp GameLoop

.do_intro:
    jmp State_Intro
.do_kitchen:
    jmp State_Kitchen
.do_baking:
    jmp State_Baking

;==========================================================
; TILA 0: INTRO / ALKUVALIKKO
;==========================================================
State_Intro:
    ; piirretaan vain kerran jos ei olla jo piirretty
    lda FRAME_COUNT
    cmp #1
    bne .wait_start

    jsr ClearScreen
    jsr DisableSprites

    ; piirra pipari merkeilla ruudun keskelle
    jsr DrawIntroCookie

    ; tekstit
    ldx #0
.it1:
    lda txt_title,x
    beq .it2
    sta SCREEN_RAM+2*40+8,x ; otsikko ylos
    inx
    jmp .it1
.it2:
    ldx #0
.it3:
    lda txt_author,x
    beq .it4
    sta SCREEN_RAM+22*40+2,x ; tekija alas
    inx
    jmp .it3
.it4:

.wait_start:
    ; vilkutetaan "PAINA L"
    lda FRAME_COUNT
    and #$10
    beq .show_l
    ldx #0
.hide_l:
    lda #32 ; space
    sta SCREEN_RAM+18*40+14,x
    inx
    cpx #13
    bne .hide_l
    jmp GameLoop
.show_l:
    ldx #0
.dl_l:
    lda txt_pressL,x
    beq .done_l
    sta SCREEN_RAM+18*40+14,x
    inx
    jmp .dl_l
.done_l:
    jmp GameLoop

DrawIntroCookie:
    ; yksinkertainen "pipari" keskelle
    ldx #6
.row_l:
    ldy #10
.col_l:
    lda #160 ; kiintea blokki
    sta SCREEN_RAM+8*40+14,y
    sta SCREEN_RAM+9*40+14,y
    sta SCREEN_RAM+10*40+14,y
    sta SCREEN_RAM+11*40+14,y
    sta SCREEN_RAM+12*40+14,y
    dey
    bne .col_l
    dex
    bne .row_l
    ; koristeet
    lda #81 ; pallo
    sta SCREEN_RAM+9*40+18
    sta SCREEN_RAM+11*40+16
    sta SCREEN_RAM+10*40+20
    rts

InitGame:
    lda #1
    sta GAME_STATE
    lda #0
    sta CYCLE_PHASE
    
    ; ukko keskelle
    lda #160
    sta PLAYER_X
    lda #150
    sta PLAYER_Y

    jsr InitKitchenSprites
    jsr DrawBakery
    jmp GameLoop

;==========================================================
; TILA 1: KEITTIO
;==========================================================
State_Kitchen:
    jsr CheckInputWASD      ; liikuta ukkoa
    jsr UpdatePlayerSprite
    jsr UpdateCarrySprite   ; karry seuraa
    jsr DrawMoney           ; paivita rahat
    jsr CheckKitchenZones   ; tarkista alueet
    jmp GameLoop

;----------------------------------------------------------
; Keittion logiikka
;----------------------------------------------------------
CheckKitchenZones:
    ; nollaa infoteksti
    jsr ClearInfoText

    ; 1. TAIKINAKONE (yla-vasen): X<100, Y<100
    lda PLAYER_X
    cmp #100
    bcs .chk_table          ; jos X>=100, poyta

    lda PLAYER_Y
    cmp #100
    bcc .mixer_y_ok         ; jos Y<100, alueella
    rts                     ; muuten ei millaan alueella
.mixer_y_ok:
    lda CYCLE_PHASE
    cmp #0
    beq .mixer_phase_ok
    rts
.mixer_phase_ok:
    jsr PrintInfo_MakeDough
    jsr CheckActionKey
    bne .no_action_mixer    ; ei RETURN -> ei toimintaa
    lda #1
    sta CYCLE_PHASE         ; taikina valmis
    rts
.no_action_mixer:
    rts

.chk_table:
    ; 2. LEIVONTAPOYTA (yla-oikea): X>220, Y<100
    lda PLAYER_X
    cmp #220
    bcc .chk_oven           ; jos X<220, ei poydalla -> mene uuniin
    lda PLAYER_Y
    cmp #100
    bcc .table_y_ok
    rts
.table_y_ok:
    lda CYCLE_PHASE
    cmp #1
    beq .table_phase_ok
    rts
.table_phase_ok:
    jsr PrintInfo_StartBake
    jsr CheckActionKey
    bne .no_action_table    ; ei RETURN -> ei toimintaa
    jsr InitMinigame        ; minipeliin
    rts
.no_action_table:
    rts

.chk_oven:
    ; 3. UUNI (ala-oikea): X>220, Y>180
    lda PLAYER_X
    cmp #220
    bcc .chk_register
    lda PLAYER_Y
    cmp #180
    bcs .oven_y_ok
    rts
.oven_y_ok:
    lda CYCLE_PHASE
    cmp #3
    beq .ready_to_bake
    cmp #4
    beq .baking_process
    rts

.ready_to_bake:
    jsr PrintInfo_StartOven
    jsr CheckActionKey
    bne .no_action_oven     ; ei RETURN -> ei toimintaa
    lda #4
    sta CYCLE_PHASE
    lda #0
    sta OVEN_TIMER
    rts
.no_action_oven:
    rts

.baking_process:
    inc OVEN_TIMER
    lda OVEN_TIMER
    cmp #250
    bcc .flash_screen
    ; valmis
    lda #5
    sta CYCLE_PHASE
    jsr ClearInfoText
    jsr PrintInfo_BakeDone
    lda #11
    sta VIC_BG_COL
    rts

.flash_screen:
    lda FRAME_COUNT
    and #$04
    beq .col1
    lda #2
    sta VIC_BG_COL
    rts
.col1:
    lda #7
    sta VIC_BG_COL
    rts

.chk_register:
    ; 4. KASSA (ala-vasen): X<100, Y>180
    lda PLAYER_X
    cmp #100
    bcc .reg_x_ok
    rts
.reg_x_ok:
    lda PLAYER_Y
    cmp #180
    bcs .reg_y_ok
    rts
.reg_y_ok:
    lda CYCLE_PHASE
    cmp #5
    beq .reg_phase_ok
    rts
.reg_phase_ok:
    jsr AddMoney
    lda #0
    sta CYCLE_PHASE

    ; voittotarkistus (1500 mk = $05DC)
    lda MONEY_LO
    cmp #$dc
    lda MONEY_HI
    cmp #$05
    bcc .not_win
    lda MONEY_LO
    cmp #$dc
    bcc .not_win
    
    ; voitto -> takaisin alkuun
    jmp State_Intro

.not_win:
    rts

;==========================================================
; TILA 2: MINIPELI (LEIVONTA)
;==========================================================
InitMinigame:
    lda #2
    sta GAME_STATE
    jsr ClearScreen

    ; nollaa tilaus
    lda #0
    sta ORDER_TGT0
    sta ORDER_TGT1
    sta ORDER_TGT2
    sta ORDER_TGT3

    ; arvo tilaus jokaiselle muodolle erikseen (0..7, alle 2 = 0 kpl)
    ldx #0
.im_rand_loop:
    lda SID_RAND
    and #$07           ; 0..7
    cmp #2
    bcc .im_zero       ; 0 tai 1 -> ei pipareita tasta muodosta
    sta ORDER_TGT0,x   ; 2..7 kpl
    jmp .im_next
.im_zero:
    lda #0
    sta ORDER_TGT0,x
.im_next:
    inx
    cpx #4
    bne .im_rand_loop

    ; varmista etta edes jotain halutaan
    lda ORDER_TGT0
    ora ORDER_TGT1
    ora ORDER_TGT2
    ora ORDER_TGT3
    bne .im_have_order

    lda #3
    sta ORDER_TGT0
.im_have_order:

    ; oletusmuotti: ensimmainen jolla tilaus > 0
    lda #0
    sta CUR_SHAPE
    ldx #0
.im_find_nonzero:
    lda ORDER_TGT0,x
    beq .im_fn_next
    stx CUR_SHAPE
    jmp .im_fn_found
.im_fn_next:
    inx
    cpx #4
    bne .im_find_nonzero
.im_fn_found:

    ; hiirikursori keskelle
    lda #160
    sta CURSOR_X
    lda #100
    sta CURSOR_Y
    lda #0
    sta MOUSE_BTN_LAST

    ; kursori-sprite (sprite 0)
    lda #194        ; kursori sprite
    sta SPRITE_PTR
    lda #1          ; valkoinen
    sta VIC_SPR_COL
    lda #1          ; vain sprite 0
    sta VIC_SPR_ENA
    
    jsr DrawMinigameUI
    rts

;---------------------------------------
; Leivonta-minipelin paasilmukka
;---------------------------------------

State_Baking:
    jsr UpdateCursorPos
    
    ; --- UUSI TOIMINTO: Pikavalinta M-näppäimellä ---
    lda #$fb        ; Portti $DC00 rivi 4 (M on täällä)
    sta $dc00
    lda $dc01
    and #$10        ; M-näppäin bitti 4
    bne .no_m_key
    ; Jos M painettu, vaihda muotti syklisesti
    inc CUR_SHAPE
    lda CUR_SHAPE
    and #$03        ; Pidä välillä 0-3
    sta CUR_SHAPE
    jsr UpdateOrderDisplay
    ; Odota hetki ettei muotti kelaa liian kovaa
    ldx #$ff
.delay: dex
    bne .delay
.no_m_key:

    jsr CheckClick
    bne .click_ok   ; Jos klikkaus (tulos ei 0), hyppää lähelle käsittelyyn
    jmp .no_click   ; Jos ei klikkausta, hyppää kauas JMP:llä (tämä yltää)

.click_ok:
    ; 1) Muotin valinta yläreunasta (Kursorilla)
    lda CURSOR_Y
    cmp #75
    bcs .check_dough 
    
    lda CURSOR_X
    lsr : lsr : lsr ; Jaetaan X-koordinaatti jotta saadaan lohkot
    cmp #10         ; Karkea jako sarakkeiden mukaan
    bcc .sel_0
    cmp #20
    bcc .sel_1
    cmp #30
    bcc .sel_2
    lda #3
    jmp .set_shape
.sel_0: lda #0
    jmp .set_shape
.sel_1: lda #1
    jmp .set_shape
.sel_2: lda #2
.set_shape:
    sta CUR_SHAPE
    jsr UpdateOrderDisplay
    jmp .no_click

.check_dough:
    ; 2) Taikinalevy
    ldx CUR_SHAPE
    lda ORDER_TGT0,x
    beq .wrong_shape

    lda CURSOR_Y
    cmp #90
    bcc .no_click
    
    dec ORDER_TGT0,x
    jsr DrawCookieMark
    jsr UpdateOrderDisplay

    lda ORDER_TGT0
    ora ORDER_TGT1
    ora ORDER_TGT2
    ora ORDER_TGT3
    bne .not_all_done

    ; KAIKKI VALMIS
    jsr ClearInfoText
    ldx #0
.bd1:
    lda txt_valmis,x
    beq .bd2
    sta SCREEN_RAM+23*40+15,x
    inx
    jmp .bd1
.bd2:
.wait_ret:
    jsr CheckActionKey
    bne .wait_ret 

    lda #3
    sta CYCLE_PHASE
    lda #1
    sta GAME_STATE
    jsr InitKitchenSprites
    jsr DrawBakery
    jmp GameLoop    ; KORJATTU: Hyppää päälooppiin, ei RTS

.not_all_done:
    jmp GameLoop    ; KORJATTU: Hyppää päälooppiin

.wrong_shape:
    lda #2 ; Punainen reuna virheen merkiksi
    sta VIC_BORDER
    jmp GameLoop    ; KORJATTU

.no_click:
    lda #0
    sta VIC_BORDER
    jmp GameLoop    ; KORJATTU: EI RTS, vaan hyppy looppiin

; Korjattu kursorin päivitys (lisätty bittitestit oikein)
UpdateCursorPos:
    ; W (Ylös)
    lda #$fd: sta $dc00: lda $dc01: and #$02: bne .c_s
    dec CURSOR_Y
.c_s:
    ; S (Alas)
    lda #$df: sta $dc00: lda $dc01: and #$20: bne .c_a
    inc CURSOR_Y
.c_a:
    ; A (Vasen)
    lda #$fd: sta $dc00: lda $dc01: and #$04: bne .c_d
    dec CURSOR_X
.c_d:
    ; D (Oikea)
    lda #$fb: sta $dc00: lda $dc01: and #$04: bne .c_upd
    inc CURSOR_X
.c_upd:
    lda CURSOR_X: sta VIC_SPR_X
    lda CURSOR_Y: sta VIC_SPR_Y
    rts

; KORJAUS: UpdateCarrySprite käytti väärää rekisteriä (+2)
UpdateCarrySprite:
    lda PLAYER_X
    clc
    adc #12
    sta VIC_SPR_X+2 ; Tämä pitäisi olla VIC_SPR_X+2 (Sprite 1 X)
    lda PLAYER_Y
    clc
    adc #5
    sta VIC_SPR_Y+2 ; Tämä pitäisi olla VIC_SPR_Y+2 (Sprite 1 Y)
    rts

;---------------------------------------
; Minipelin UI ja tilauksen naytto
;---------------------------------------
DrawMinigameUI:
    ; muottien nimet (ylariviin)
    ldx #0
.dm1:
    lda txt_tools,x
    beq .dm2
    sta SCREEN_RAM+2,x
    inx
    jmp .dm1
.dm2:
    ; "asiakas toivoo: "
    ldx #0
.dm3:
    lda txt_req,x
    beq .dm4
    sta SCREEN_RAM+3*40+2,x
    inx
    jmp .dm3
.dm4:
    ; nayta valitun muotin nimi ja maara
    jsr UpdateOrderDisplay

    ; taikinalevy (yksi levea palkki)
    ldx #12
.dl1:
    ldy #30
    lda #160
.dl2:
    sta SCREEN_RAM+8*40+5,y
    pha
    lda #1
    sta COLOR_RAM+8*40+5,y
    pla
    dey
    bne .dl2
    rts

; Paivittaa "asiakas toivoo" -riville valitun muotin nimen ja jaljella olevan maaran
UpdateOrderDisplay:
    ; tyhjenna sarakkeet 18..39 tahan riville
    ldx #0
    lda #32
.uod_clr:
    sta SCREEN_RAM+3*40+18,x
    inx
    cpx #22          ; 22 merkia (kolumnit 18..39)
    bne .uod_clr

    ; hae nimen osoitin CUR_SHAPE:n perusteella (low/high taulukoista)
    ldx CUR_SHAPE
    lda ShapeNameLo,x
    sta TEXT_PTR_LO
    lda ShapeNameHi,x
    sta TEXT_PTR_HI

    ldy #0
.uod_name:
    lda (TEXT_PTR_LO),y
    beq .uod_after_name
    sta SCREEN_RAM+3*40+18,y
    iny
    jmp .uod_name
.uod_after_name:
    ; valilyonti nimen jalkeen
    lda #32
    sta SCREEN_RAM+3*40+18,y
    iny

    ; tulosta jaljella oleva maara tasta muodosta
    ldx CUR_SHAPE
    lda ORDER_TGT0,x     ; 0..7
    clc
    adc #48              ; ASCII '0'
    sta SCREEN_RAM+3*40+18,y
    rts

DrawCookieMark:
    ; pieni visuaalinen efekti (voit myohemmin piirtää oikean piparin)
    inc VIC_BG_COL
    rts

;==========================================================
; YLEISET RUTIINIT
;==========================================================

CheckInputWASD:
    ; W (ylos)
    lda #$fd
    sta $dc00
    lda $dc01
    and #$02
    bne .check_s
    dec PLAYER_Y
.check_s:
    ; S (alas)
    lda #$df
    sta $dc00
    lda $dc01
    and #$20
    bne .check_a
    inc PLAYER_Y
.check_a:
    ; A (vasen)
    lda #$fd
    sta $dc00
    lda $dc01
    and #$04
    bne .check_d
    dec PLAYER_X
.check_d:
    ; D (oikea)
    lda #$fb
    sta $dc00
    lda $dc01
    and #$04
    bne .done_move
    inc PLAYER_X
.done_move:
    rts

CheckActionKey:
    ; Return (Row 0, Col 1)
    lda #$fe
    sta $dc00
    lda $dc01
    and #$02
    ; tulkinta:
    ; - RETURN painettu  -> tulos 0  -> Z=1
    ; - ei painettu      -> tulos !=0-> Z=0
    rts

; Palauttaa A=1 jos talla framella tuli UUSI klik (RETURN painettu nyt,
; mutta ei viime framella). Muulloin A=0.
CheckClick:
    jsr CheckActionKey      ; Z=1 jos RETURN painettu
    bne .not_pressed        ; ei painettu -> ei klikkia

    ; RETURN on painettu
    lda MOUSE_BTN_LAST
    bne .already_down       ; oli jo edellisella framella -> ei uutta klikkia
    lda #1
    sta MOUSE_BTN_LAST      ; merkitään alas
    lda #1                  ; uusi klikki
    rts

.already_down:
    lda #0
    rts

.not_pressed:
    lda #0
    sta MOUSE_BTN_LAST      ; nappi ylhaalla
    rts

InitKitchenSprites:
    lda #3          ; sprite 0 ja 1 paalle
    sta VIC_SPR_ENA
    lda #192        ; ukko
    sta SPRITE_PTR
    lda #1          ; valkoinen
    sta VIC_SPR_COL
    lda #193        ; karry
    sta SPRITE_PTR+1
    lda #9          ; ruskea
    sta VIC_SPR_COL+1
    rts

UpdatePlayerSprite:
    lda PLAYER_X
    sta VIC_SPR_X
    lda PLAYER_Y
    sta VIC_SPR_Y
    rts

DrawBakery:
    jsr ClearScreen
    ; kiinteat tekstit
    ldx #0
.db1:
    lda txt_mixer,x
    beq .db2
    sta SCREEN_RAM+2*40+2,x
    inx
    jmp .db1
.db2:
    ldx #0
.db3:
    lda txt_table,x
    beq .db4
    sta SCREEN_RAM+2*40+25,x
    inx
    jmp .db3
.db4:
    ldx #0
.db5:
    lda txt_reg,x
    beq .db6
    sta SCREEN_RAM+20*40+2,x
    inx
    jmp .db5
.db6:
    ldx #0
.db7:
    lda txt_oven,x
    beq .db8
    sta SCREEN_RAM+20*40+30,x
    inx
    jmp .db7
.db8:
    rts

DrawMoney:
    ; "RAHA:" + arvo ylariville (heksana)
    lda #18 ; 'R' (PETSCII)
    sta SCREEN_RAM
    lda MONEY_HI
    jsr PrintHex
    sta SCREEN_RAM+2
    stx SCREEN_RAM+3
    lda MONEY_LO
    jsr PrintHex
    sta SCREEN_RAM+4
    stx SCREEN_RAM+5
    rts

AddMoney:
    sed
    clc
    ; yksinkertainen laskuri: high-byte kasvaa 1 (100 mk portaissa)
    lda MONEY_HI
    adc #$01
    sta MONEY_HI
    cld
    rts

PrintHex:
    pha
    lsr
    lsr
    lsr
    lsr
    tax
    lda HexChars,x
    tay
    pla
    and #$0f
    tax
    lda HexChars,x
    tax
    tya
    rts

ClearScreen:
    ldx #0
.cs1:
    lda #32         ; space
    sta SCREEN_RAM,x
    sta SCREEN_RAM+250,x
    sta SCREEN_RAM+500,x
    sta SCREEN_RAM+750,x

    lda #1          ; valkoinen vari
    sta COLOR_RAM,x
    sta COLOR_RAM+250,x
    sta COLOR_RAM+500,x
    sta COLOR_RAM+750,x

    inx
    bne .cs1
    rts

ClearInfoText:
    ldx #0
    lda #32
.ci1:
    sta SCREEN_RAM+24*40,x
    inx
    cpx #39
    bne .ci1
    rts

PrintInfo_MakeDough:
    ldx #0
.pi1:
    lda txt_inf1,x
    beq .done1
    sta SCREEN_RAM+24*40+1,x
    inx
    jmp .pi1
.done1:
    rts

PrintInfo_StartBake:
    ldx #0
.pi2:
    lda txt_inf2,x
    beq .done2
    sta SCREEN_RAM+24*40+1,x
    inx
    jmp .pi2
.done2:
    rts

PrintInfo_StartOven:
    ldx #0
.pi3:
    lda txt_inf3,x
    beq .done3
    sta SCREEN_RAM+24*40+1,x
    inx
    jmp .pi3
.done3:
    rts

PrintInfo_BakeDone:
    ldx #0
.pi4:
    lda txt_inf4,x
    beq .done4
    sta SCREEN_RAM+24*40+1,x
    inx
    jmp .pi4
.done4:
    rts

DisableSprites:
    lda #0
    sta VIC_SPR_ENA
    rts

;==========================================================
; DATA
;==========================================================

txt_title:  !scr "joulupiparipeli demo",0
txt_author: !scr "tehnyt jani malmberg",0
txt_pressL: !scr "paina l",0

txt_mixer:  !scr "taikinakone",0
txt_table:  !scr "leivontapoyta",0
txt_oven:   !scr "uuni",0
txt_reg:    !scr "kassa",0

txt_inf1:   !scr "valmista taikina (return)",0
txt_inf2:   !scr "aloita leivonta (return)",0
txt_inf3:   !scr "aloita paistaminen (return)",0
txt_inf4:   !scr "paisto valmis!",0

txt_tools:  !scr " syd   kel   enk   kuu",0
txt_req:    !scr "asiakas toivoo: ",0
txt_valmis: !scr "valmis (return)",0

; Muottien nimet
shape_name0: !scr "sydan",0
shape_name1: !scr "kello",0
shape_name2: !scr "enkeli",0
shape_name3: !scr "kuusi",0

; Low- ja high-byte taulukot muottien nimien osoitteille
ShapeNameLo:
    !byte <shape_name0, <shape_name1, <shape_name2, <shape_name3
ShapeNameHi:
    !byte >shape_name0, >shape_name1, >shape_name2, >shape_name3

; Osoitintaulukko muottien nimille (2 tavua / merkki)
ShapeNamePtrs:
    !word shape_name0, shape_name1, shape_name2, shape_name3

HexChars:   !text "0123456789abcdef"

;--- SPRITE DATAT ($3000 -> 12288) ---
* = $3000
    ; Sprite 0 (192): Leipuri
    !byte 0,60,0, 0,66,0, 0,129,0, 0,129,0, 0,66,0, 0,60,0
    !byte 3,255,192, 4,0,32, 8,0,16, 16,0,8, 16,0,8, 16,0,8, 16,0,8
    !byte 31,255,248, 4,0,32, 4,0,32, 4,0,32, 6,0,96, 0,0,0, 0,0,0, 0

* = $3040
    ; Sprite 1 (193): Karry
    !byte 0,0,0, 0,0,0, 0,0,0, 63,255,252, 32,0,4, 32,36,4
    !byte 32,0,4, 32,144,4, 32,0,4, 63,255,252, 0,0,0, 2,0,64
    !byte 2,0,64, 5,0,160, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0

* = $3080
    ; Sprite 2 (194): Kursori
    !byte 16,0,0, 24,0,0, 28,0,0, 30,0,0, 31,0,0, 28,0,0
    !byte 24,0,0, 16,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0
    !byte 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0,0,0, 0