/**
 * HILO Ativador (mercado B3).
 *
 * Média móvel das máximas (HI, vermelho) e das mínimas (LO, verde) de X
 * períodos, deslocada Y períodos à frente (adiantada), desenhada como linha
 * contínua, sem escada.
 *
 * Regra do ativador: em alta, quando o fechamento cruza abaixo do LO o estado
 * vira baixa e o HI passa a ser o ativador (resistência); em baixa, quando o
 * fechamento cruza acima do HI o estado vira alta e o LO passa a ser o
 * ativador (suporte). No HILO clássico o lado inativo desaparece do gráfico;
 * aqui ele permanece visível TRACEJADO, então o trader vê a linha completa e
 * ainda sabe qual lado está ativo.
 *
 * Indicador customizado do gráfico do OpenAlgo: arquivo de usuário em
 * strategies/indicators, carregado em runtime sem qualquer modificação no core.
 */

export default function ({ registerIndicator, sourceValues, sma }) {
  registerIndicator({
    id: 'b3-hilo-ativador',
    name: 'HILO Ativador',
    category: 'Custom',
    placement: 'onchart',

    inputs: [
      {
        key: 'length',
        type: 'number',
        label: 'Períodos (X)',
        default: 10,
        min: 1,
        max: 400,
        step: 1,
        tooltip: 'Quantidade de períodos da média móvel das máximas (HI) e das mínimas (LO).',
      },
      {
        key: 'shift',
        type: 'number',
        label: 'Adiantamento (Y)',
        default: 1,
        min: 0,
        max: 100,
        step: 1,
        tooltip: 'Períodos adiantados: a linha na barra i é a média calculada até a barra i-Y. 0 = sem deslocamento.',
      },
      {
        key: 'confirmColor',
        type: 'boolean',
        label: 'Confirmar por cor do candle',
        default: false,
        tooltip: 'Se ativo, a reversão só vale quando o candle confirma: rev. p/ alto exige candle azul (close > open), rev. p/ baixo exige vermelho (close < open). Dojis e cores contrárias são ignorados até o próximo gatilho. Desativado = comportamento clássico do HILO.',
      },
    ],

    plots: [
      {
        key: 'hi',
        type: 'line',
        title: 'HI',
        style: { color: '#ef5350', lineWidth: 2 },
        tooltip: 'Média das máximas, ativa (ativador) quando o estado é baixa.',
      },
      {
        key: 'hiGhost',
        type: 'line',
        title: 'HI (inativo)',
        style: { color: '#ef5350', lineWidth: 1, lineStyle: 'dashed' },
        tooltip: 'Média das máximas no trecho que a regra do ativador esconderia.',
      },
      {
        key: 'lo',
        type: 'line',
        title: 'LO',
        style: { color: '#26a69a', lineWidth: 2 },
        tooltip: 'Média das mínimas, ativa (ativador) quando o estado é alta.',
      },
      {
        key: 'loGhost',
        type: 'line',
        title: 'LO (inativo)',
        style: { color: '#26a69a', lineWidth: 1, lineStyle: 'dashed' },
        tooltip: 'Média das mínimas no trecho que a regra do ativador esconderia.',
      },
    ],

    calc(bars, settings) {
      const n = bars.length
      const length = Math.max(1, Math.floor(Number(settings.length) || 10))
      const shift = Math.max(0, Math.floor(Number(settings.shift) ?? 1))
      const confirmColor = Boolean(settings.confirmColor)

      const highs = sourceValues(bars, 'high')
      const lows = sourceValues(bars, 'low')
      const closes = sourceValues(bars, 'close')
      const opens = sourceValues(bars, 'open')

      // Médias móveis simples das máximas e mínimas.
      const maHigh = sma(highs, length)
      const maLow = sma(lows, length)

      // Linha adiantada: o valor na barra i é a média calculada até i-Y.
      // Isso desloca a média Y barras à frente sem usar escada (step).
      const hi = new Array(n).fill(null)
      const lo = new Array(n).fill(null)
      for (let i = shift; i < n; i += 1) {
        hi[i] = maHigh[i - shift]
        lo[i] = maLow[i - shift]
      }

      // Estado do ativador: 'up' (LO ativo) / 'down' (HI ativo) / null antes do
      // primeiro gatilho. Histerese clássica do HILO: em alta só vira baixa se o
      // fechamento cair abaixo do LO; em baixa só vira alta se passar do HI.
      // Confirmacao por cor (opcional): a transicao so vale se o candle
      // confirmar (azul para virar alta, vermelho para virar baixa). Doji
      // (open == close) nunca confirma; o gatilho fica esperando o proximo
      // candle que cruze E confirme. Com a opcao desligada vale a regra
      // classica, que olha so o fechamento.
      const state = new Array(n).fill(null)
      for (let i = 0; i < n; i += 1) {
        const prev = i > 0 ? state[i - 1] : null
        const h = hi[i]
        const l = lo[i]
        const c = closes[i]
        const o = opens[i]
        if (h == null || l == null || c == null) {
          state[i] = prev
          continue
        }
        const azul = o != null && c > o
        const vermelho = o != null && c < o
        if (prev === 'up') {
          const viraBaixa = c < l && (!confirmColor || vermelho)
          state[i] = viraBaixa ? 'down' : 'up'
        } else if (prev === 'down') {
          const viraAlta = c > h && (!confirmColor || azul)
          state[i] = viraAlta ? 'up' : 'down'
        } else if (c > h && (!confirmColor || azul)) state[i] = 'up'
        else if (c < l && (!confirmColor || vermelho)) state[i] = 'down'
        else state[i] = null
      }

      // Colunas sólida/tracejada por lado. O trecho ativo fica sólido; o
      // inativo, tracejado. Nas barras de transição o valor entra nas duas
      // colunas para os segmentos se conectarem e a linha parecer contínua.
      const hiSolid = new Array(n).fill(null)
      const hiGhost = new Array(n).fill(null)
      const loSolid = new Array(n).fill(null)
      const loGhost = new Array(n).fill(null)
      for (let i = 0; i < n; i += 1) {
        const s = state[i]
        const prev = i > 0 ? state[i - 1] : null
        if (hi[i] != null) {
          const solid = s === 'down' || (prev === 'down' && s !== 'down')
          if (solid) hiSolid[i] = hi[i]
          if (!solid || prev === 'down') hiGhost[i] = hi[i]
        }
        if (lo[i] != null) {
          const solid = s === 'up' || (prev === 'up' && s !== 'up')
          if (solid) loSolid[i] = lo[i]
          if (!solid || prev === 'up') loGhost[i] = lo[i]
        }
      }

      return { hi: hiSolid, hiGhost, lo: loSolid, loGhost }
    },
  })
}
