; ===========================================================================
;  Barras de vida dos inimigos (hack) - v2
;
;  HUD estilo Final Fight abaixo de "STAGE": nome + barra do ultimo
;     inimigo atingido (plano A, que nao rola)
;
;  Dados do jogo usados:
;  - Inimigos: slots $FFD100-$FFD4FF, tipos $2E-$4C (byte 0 & $7F)
;  - Nomes: exatamente como nos creditos finais do jogo
;  - Vida atual: byte $64(a0)
;  - Vida maxima: guardada pelo hack em $7E(a0) (byte nunca usado pelo jogo)
;
;  VRAM usada (livre durante as fases, verificado nas fases 1-3):
;  - $B380-$B3FF: 4 tiles da barra (cheio, 6px, 4px, 2px)  -> $59C-$59F
;  - $AB80-$AB9F: 1 tile de barra vazia                    -> $55C
;  - $BE00-$BFFF: 16 tiles onde o nome e montado           -> $5F0-$5FF
;    (area do jogador 2: o nome so e mostrado em jogo de 1 jogador)
; ===========================================================================

HB_TILE_FULL	= $59C		; + (4-unidades) para 3..1 unidades
HB_TILE_EMPTY	= $55C
HB_TILE_NAME	= $5F0
HB_NAME_LEN	= 16
HB_BAR_CELLS	= 8
HB_SHOW_TIME	= 180		; frames que o HUD fica visivel apos o ultimo golpe

; RAM livre (bloco $FFC4A0-$FFC6FF nunca e usado pelo jogo)
HB_Target	= $FFFFC680	; w: endereco (16 bits) do inimigo alvo, 0 = nenhum
HB_Timer	= $FFFFC682	; w
HB_Shown	= $FFFFC684	; b: HUD desenhado na tela
HB_NameId	= $FFFFC685	; b: nome atualmente montado na VRAM (0 = nenhum)
HB_LastHP	= $FFFFC688	; 8 bytes: vida no frame anterior, por slot

; Comandos de escrita na VRAM
HB_CMD_ROW4	= $42020003	; plano A ($C000), linha 4, coluna 1
HB_CMD_ROW5	= $42820003	; plano A, linha 5, coluna 1
HB_CMD_NAME	= $7E000002	; VRAM $BE00
HB_CMD_TILES	= $73800002	; VRAM $B380
HB_CMD_EMPTY	= $6B800002	; VRAM $AB80

VDP_DATA	= $00C00000
VDP_CTRL	= $00C00004

; ---------------------------------------------------------------------------
; Chamado no lugar do final de loc_B7F8 (montagem do buffer de sprites).
; ---------------------------------------------------------------------------
HealthBars:
	move.l	a3, -(sp)
	movea.w	$FFFFC184.w, a2
	lea	$FFFFD100.w, a0
	lea	(HB_LastHP).w, a3
	moveq	#7, d6
HB_Loop:
	moveq	#0, d0
	move.b	(a0), d0
	bpl.w	HB_Next			; vazio ou ainda nao inicializado
	andi.b	#$7F, d0
	cmpi.b	#$2E, d0
	bcs.w	HB_Next
	cmpi.b	#$4C, d0
	bhi.w	HB_Next
HB_IsEnemy:
	moveq	#0, d1
	move.b	$64(a0), d1		; vida atual
	moveq	#0, d2
	move.b	$7E(a0), d2		; vida maxima registrada
	bne.s	HB_Known
	; primeira vez que vemos este inimigo
	tst.b	d1
	beq.w	HB_Next
	move.b	d1, $7E(a0)
	move.w	d1, d2
	move.b	d1, (a3)
HB_Known:
	cmp.w	d2, d1
	bls.s	HB_MaxOk
	move.b	d1, $7E(a0)
	move.w	d1, d2
HB_MaxOk:
	; levou dano neste frame? vira o alvo do HUD
	cmp.b	(a3), d1
	bcc.s	HB_NoHit
	move.w	a0, (HB_Target).w
	move.w	#HB_SHOW_TIME, (HB_Timer).w
HB_NoHit:
	move.b	d1, (a3)
HB_Next:
	lea	$80(a0), a0
	addq.w	#1, a3
	dbf	d6, HB_Loop

	bsr.w	HB_UpdateHUD

	; final original de loc_B7F8: sprite terminador
	clr.l	(a2)+
	clr.l	(a2)+
	move.w	a2, $FFFFC184.w
	movea.l	(sp)+, a3
	rts

; Tile da barra para d5 unidades (0-4) -> d0
HB_UnitTile:
	move.w	#HB_TILE_EMPTY, d0
	tst.w	d5
	beq.s	HB_UnitTileEnd
	move.w	#HB_TILE_FULL+4, d0
	sub.w	d5, d0
HB_UnitTileEnd:
	rts

; ---------------------------------------------------------------------------
; HUD: nome + barra do alvo, no plano A abaixo de "STAGE"
; ---------------------------------------------------------------------------
HB_UpdateHUD:
	cmpi.b	#$C, $FFFFC173.w	; so durante a fase
	beq.s	HB_HudActive
	clr.w	(HB_Target).w
	clr.b	(HB_Shown).w
	rts
HB_HudActive:
	move.w	(HB_Target).w, d0
	beq.w	HB_HudHide
	movea.w	d0, a0
	; o objeto ainda e um inimigo?
	moveq	#0, d0
	move.b	(a0), d0
	bpl.w	HB_HudDrop
	andi.b	#$7F, d0
	cmpi.b	#$2E, d0
	bcs.w	HB_HudDrop
	cmpi.b	#$4C, d0
	bhi.w	HB_HudDrop
HB_HudOk:
	subq.w	#1, (HB_Timer).w
	bls.w	HB_HudDrop
	; --- nome (so com 1 jogador: a area de tiles e a do jogador 2) ---
	tst.b	$FFFFD080.w
	bne.s	HB_HudBar
	subi.b	#$2E, d0
	lea	HB_TypeName(pc), a1
	move.b	(a1,d0.w), d0		; id do nome (1..n), ou especial
	beq.s	HB_HudBar
	bpl.s	HB_HudNameId
	bsr.w	HB_ClassifyByPalette	; cavaleiros / Death Adder: pela cor
HB_HudNameId:
	cmp.b	(HB_NameId).w, d0
	beq.s	HB_HudNameRow
	move.b	d0, (HB_NameId).w
	bsr.w	HB_BuildName
HB_HudNameRow:
	move	sr, -(sp)
	ori	#$700, sr
	move.l	#HB_CMD_ROW4, VDP_CTRL
	move.w	#$8000|HB_TILE_NAME, d0
	moveq	#HB_NAME_LEN-1, d1
HB_NameCell:
	move.w	d0, VDP_DATA
	addq.w	#1, d0
	dbf	d1, HB_NameCell
	move	(sp)+, sr
HB_HudBar:
	; --- barra: nivel = teto(vida*32/max), 0..32 ---
	moveq	#0, d1
	move.b	$64(a0), d1
	moveq	#0, d2
	move.b	$7E(a0), d2
	bne.s	HB_HudMax
	moveq	#1, d2
HB_HudMax:
	lsl.w	#5, d1
	beq.s	HB_HudLevel
	add.w	d2, d1
	subq.w	#1, d1
	divu.w	d2, d1
HB_HudLevel:
	move	sr, -(sp)
	ori	#$700, sr
	move.l	#HB_CMD_ROW5, VDP_CTRL
	moveq	#HB_BAR_CELLS-1, d6
HB_BarCell:
	move.w	d1, d5			; unidades desta celula = clamp(nivel,0,4)
	bpl.s	HB_BarPos
	moveq	#0, d5
HB_BarPos:
	cmpi.w	#4, d5
	ble.s	HB_BarClamp
	moveq	#4, d5
HB_BarClamp:
	bsr.w	HB_UnitTile
	ori.w	#$8000, d0
	move.w	d0, VDP_DATA
	subq.w	#4, d1
	dbf	d6, HB_BarCell
	move	(sp)+, sr
	st	(HB_Shown).w
	rts

HB_TypeName:	; tipo $2E..$4C -> id do nome em HB_NameTable (a partir de 1)
	dc.b	1,1,1			; $2E-$30 SKELETON
	dc.b	2,3,4,5,6,7,8		; $31-$37 LONGMOAN (6 cores + montado)
	dc.b	9,10,11,12,13,14,15	; $38-$3E HENINGER (6 cores + montado)
	dc.b	16,17,18		; $3F-$41 gigantes
	dc.b	19,20,21,22,19		; $42-$46 amazonas (4 + montada)
	dc.b	$FE,$FE,$FE		; $47-$49 cavaleiros: decidido pela cor
	dc.b	$FD,$FD,$FD		; $4A-$4C Death Adder: decidido pela cor
	even

; Escolhe o nome pela cor 12 da paleta 1 (armadura), como nos creditos.
; Entrada: d0 = $FE (cavaleiros) ou $FD (Death Adder). Saida: d0 = id.
HB_ClassifyByPalette:
	move.w	$FFFFC038.w, d1		; paleta 1, cor 12 (formato 0BBB0GGG0RRR0)
	move.w	d1, d2
	lsr.w	#1, d2
	andi.w	#7, d2			; d2 = R
	move.w	d1, d3
	lsr.w	#5, d3
	andi.w	#7, d3			; d3 = G
	lsr.w	#8, d1
	lsr.w	#1, d1
	andi.w	#7, d1			; d1 = B
	cmpi.b	#$FE, d0
	bne.s	HB_ClassDeath
	; Lt. (cinza $CCC) / Col. (vermelho $88E) / Gen. (dourado $2CC)
	moveq	#25, d0			; GEN.BITTER
	cmpi.w	#2, d1
	bls.s	HB_ClassEnd
	moveq	#24, d0			; COL.BITTER
	move.w	d3, d4
	addq.w	#1, d4
	cmp.w	d4, d2
	bhi.s	HB_ClassEnd
	moveq	#23, d0			; LT.BITTER
	rts
HB_ClassDeath:
	; Jr. (azul $A84) / Death Adder (vermelho $66E) / Death Bringer (magenta $C4E)
	moveq	#26, d0			; DEATH ADDER JR.
	cmpi.w	#6, d2
	bcs.s	HB_ClassEnd
	moveq	#27, d0			; DEATH ADDER
	cmpi.w	#5, d1
	bcs.s	HB_ClassEnd
	moveq	#28, d0			; DEATH BRINGER
HB_ClassEnd:
	rts

HB_HudDrop:
	clr.w	(HB_Target).w
HB_HudHide:
	tst.b	(HB_Shown).w
	beq.s	HB_HudEnd
	clr.b	(HB_Shown).w
	move	sr, -(sp)
	ori	#$700, sr
	move.l	#HB_CMD_ROW4, VDP_CTRL
	moveq	#HB_NAME_LEN-1, d1
HB_ClrName:
	move.w	#0, VDP_DATA
	dbf	d1, HB_ClrName
	move.l	#HB_CMD_ROW5, VDP_CTRL
	moveq	#HB_BAR_CELLS-1, d1
HB_ClrBar:
	move.w	#0, VDP_DATA
	dbf	d1, HB_ClrBar
	move	(sp)+, sr
HB_HudEnd:
	rts

; Monta o nome d0 (id) nos 12 tiles da VRAM $BE80
HB_BuildName:
	movem.l	d0-d2/a0-a1, -(sp)
	andi.w	#$FF, d0
	add.w	d0, d0
	lea	HB_NameTable(pc), a0
	adda.w	-2(a0,d0.w), a0		; a0 = string
	move	sr, -(sp)
	ori	#$700, sr
	move.l	#HB_CMD_NAME, VDP_CTRL
	moveq	#HB_NAME_LEN-1, d2
HB_BuildChar:
	moveq	#0, d0
	move.b	(a0), d0
	beq.s	HB_BuildBlank		; fim da string: completa com vazio
	addq.w	#1, a0
	cmpi.b	#'.', d0
	bne.s	HB_BuildNotDot
	moveq	#36, d0			; '.'
	bra.s	HB_BuildGlyph
HB_BuildNotDot:
	subi.b	#'0', d0
	bcs.s	HB_BuildBlank		; espaco
	cmpi.b	#9, d0
	bls.s	HB_BuildGlyph
	subq.b	#'A'-'0'-10, d0		; 'A' -> 10
	cmpi.b	#35, d0
	bhi.s	HB_BuildBlank
HB_BuildGlyph:
	lsl.w	#5, d0
	lea	HB_Font(pc), a1
	adda.w	d0, a1
	moveq	#7, d1
HB_GlyphRow:
	move.l	(a1)+, VDP_DATA
	dbf	d1, HB_GlyphRow
	bra.s	HB_BuildNext
HB_BuildBlank:
	moveq	#7, d1
HB_BlankRow:
	move.l	#0, VDP_DATA
	dbf	d1, HB_BlankRow
HB_BuildNext:
	dbf	d2, HB_BuildChar
	move	(sp)+, sr
	movem.l	(sp)+, d0-d2/a0-a1
	rts

HB_NameTable:	; offsets relativos a HB_NameTable (nomes dos creditos finais)
	dc.w	HB_Name1-HB_NameTable
	dc.w	HB_Name2-HB_NameTable
	dc.w	HB_Name3-HB_NameTable
	dc.w	HB_Name4-HB_NameTable
	dc.w	HB_Name5-HB_NameTable
	dc.w	HB_Name6-HB_NameTable
	dc.w	HB_Name7-HB_NameTable
	dc.w	HB_Name8-HB_NameTable
	dc.w	HB_Name9-HB_NameTable
	dc.w	HB_Name10-HB_NameTable
	dc.w	HB_Name11-HB_NameTable
	dc.w	HB_Name12-HB_NameTable
	dc.w	HB_Name13-HB_NameTable
	dc.w	HB_Name14-HB_NameTable
	dc.w	HB_Name15-HB_NameTable
	dc.w	HB_Name16-HB_NameTable
	dc.w	HB_Name17-HB_NameTable
	dc.w	HB_Name18-HB_NameTable
	dc.w	HB_Name19-HB_NameTable
	dc.w	HB_Name20-HB_NameTable
	dc.w	HB_Name21-HB_NameTable
	dc.w	HB_Name22-HB_NameTable
	dc.w	HB_Name23-HB_NameTable
	dc.w	HB_Name24-HB_NameTable
	dc.w	HB_Name25-HB_NameTable
	dc.w	HB_Name26-HB_NameTable
	dc.w	HB_Name27-HB_NameTable
	dc.w	HB_Name28-HB_NameTable
HB_Name1:	dc.b	"SKELETON",0
HB_Name2:	dc.b	"SILVER LONGMOAN",0
HB_Name3:	dc.b	"PURPLE LONGMOAN",0
HB_Name4:	dc.b	"RED LONGMOAN",0
HB_Name5:	dc.b	"GOLD LONGMOAN",0
HB_Name6:	dc.b	"DARK LONGMOAN",0
HB_Name7:	dc.b	"BRONZE LONGMOAN",0
HB_Name8:	dc.b	"LONGMOAN",0
HB_Name9:	dc.b	"HENINGER SILVER",0
HB_Name10:	dc.b	"HENINGER PURPLE",0
HB_Name11:	dc.b	"HENINGER RED",0
HB_Name12:	dc.b	"HENINGER GOLD",0
HB_Name13:	dc.b	"HENINGER DARK",0
HB_Name14:	dc.b	"HENINGER BRONZE",0
HB_Name15:	dc.b	"HENINGER",0
HB_Name16:	dc.b	"BAD BROTHERS",0
HB_Name17:	dc.b	"SGT.MALT AND HOP",0
HB_Name18:	dc.b	"GEN.HEARTLAND",0
HB_Name19:	dc.b	"STORCHINAYA",0
HB_Name20:	dc.b	"STROBAYA",0
HB_Name21:	dc.b	"LEMANAYA",0
HB_Name22:	dc.b	"GRUZIYA",0
HB_Name23:	dc.b	"LT.BITTER",0
HB_Name24:	dc.b	"COL.BITTER",0
HB_Name25:	dc.b	"GEN.BITTER",0
HB_Name26:	dc.b	"DEATH ADDER JR.",0
HB_Name27:	dc.b	"DEATH ADDER",0
HB_Name28:	dc.b	"DEATH BRINGER",0
	even

; ---------------------------------------------------------------------------
; Chamado no lugar de "jsr loc_2FC8" que carrega a fonte/HUD em VRAM $B000
; (inicio de cada fase).
; ---------------------------------------------------------------------------
HB_LoadTiles:
	jsr	(loc_2FC8).l
	movem.l	d1/a1, -(sp)
	move	sr, -(sp)
	ori	#$700, sr
	move.w	#$8F02, VDP_CTRL
	move.l	#HB_CMD_TILES, VDP_CTRL
	lea	(HB_Tiles).l, a1
	moveq	#(4*8)-1, d1
HB_TileLoop:
	move.l	(a1)+, VDP_DATA
	dbf	d1, HB_TileLoop
	move.l	#HB_CMD_EMPTY, VDP_CTRL
	moveq	#8-1, d1
HB_EmptyLoop:
	move.l	(a1)+, VDP_DATA
	dbf	d1, HB_EmptyLoop
	move	(sp)+, sr
	clr.w	(HB_Target).w
	clr.w	(HB_Shown).w		; zera HB_Shown e HB_NameId
	movem.l	(sp)+, d1/a1
	rts

HB_Tiles:
	include	"hb_tiles.inc"
	include	"hb_tile_empty.inc"
	include	"hb_font.inc"
	even

; ---------------------------------------------------------------------------
; Opcional: comecar o jogo em outra fase (montar com -D START_STAGE=n)
; ---------------------------------------------------------------------------
	if START_STAGE>1
HB_StartStage:
	clr.w	$FFFFC19C.w
	move.w	#START_STAGE-1, $FFFFFE2C.w	; $FE2D = fase (0 = fase 1)
	rts
	endif
