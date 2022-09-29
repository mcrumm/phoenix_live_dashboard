import { ColorWheel, LineColor } from './color_wheel'
import uPlot from 'uplot'

const SeriesValue = (options) => {
  if (!options.unit) return {}

  return {
    value: (u, v) => v == null ? '--' : v.toFixed(3) + ` ${options.unit}`
  }
}

const XSeriesValue = (options) => {
  return {
    value: '{YYYY}-{MM}-{DD} {HH}:{mm}:{ss}'
  }
}

const YAxisValue = (options) => {
  if (!options.unit) return {}

  return {
    values: (u, vals, space) => vals.map(v => +v.toFixed(2) + ` ${options.unit}`)
  }
}

const XAxis = (_options) => {
  return {
    space: 55,
    values: [
      [3600 * 24 * 365, "{YYYY}", 7, "{YYYY}"],
      [3600 * 24 * 28, "{MMM}", 7, "{MMM}\n{YYYY}"],
      [3600 * 24, "{MM}-{DD}", 7, "{MM}-{DD}\n{YYYY}"],
      [3600, "{HH}:{mm}", 4, "{HH}:{mm}\n{YYYY}-{MM}-{DD}"],
      [60, "{HH}:{mm}", 4, "{HH}:{mm}\n{YYYY}-{MM}-{DD}"],
      [1, "{ss}", 2, "{HH}:{mm}:{ss}\n{YYYY}-{MM}-{DD}"],
    ]
  }
}

const YAxis = (options) => {
  return {
    show: true,
    size: 70,
    space: 15,
    ...YAxisValue(options)
  }
}

const minChartSize = {
  width: 100,
  height: 300
}

// Limits how often a function is invoked
function throttle(cb, limit) {
  let wait = false;

  return () => {
    if (!wait) {
      requestAnimationFrame(cb);
      wait = true;
      setTimeout(() => {
        wait = false;
      }, limit);
    }
  }
}

export const newSeriesConfig = (options, index = 0) => {
  return {
    ...LineColor.at(index),
    ...SeriesValue(options),
    label: options.label,
    spanGaps: true,
    points: { show: false }
  }
}

/** Telemetry Metrics **/

// Maps an ordered list of dataset objects into an ordered list of data points.
const dataForDatasets = (datasets) => datasets.slice(0).map(({ data }) => data)

// Handler for an untagged CommonMetric
function nextValueForCallback({ y, z }, callback) {
  this.datasets[0].data.push(z)
  let currentValue = this.datasets[1].data[this.datasets[1].data.length - 1] || 0
  let nextValue = callback.call(this, y, currentValue)
  this.datasets[1].data.push(nextValue)
}

const findLastNonNullValue = (data) => data.reduceRight((a, c) => (c != null && a == null ? c : a), null)

// Handler for a tagged CommonMetric
function nextTaggedValueForCallback({ x, y, z }, callback) {
  // Find or create the series from the tag
  let seriesIndex = this.datasets.findIndex(({ key }) => x === key)
  if (seriesIndex === -1) {
    seriesIndex = this.datasets.push({ key: x, data: Array(this.datasets[0].data.length).fill(null) }) - 1
    this.chart.addSeries(newSeriesConfig({ label: x, unit: this.options.unit }, seriesIndex - 1), seriesIndex)
  }

  // Add the new timestamp + value, keeping datasets aligned
  this.datasets = this.datasets.map((dataset, index) => {
    if (index === 0) {
      dataset.data.push(z)
    } else if (index === seriesIndex) {
      dataset.data.push(callback.call(this, y, findLastNonNullValue(dataset.data) || 0))
    } else {
      dataset.data.push(null)
    }
    return dataset
  })
}

const getPruneThreshold = ({ pruneThreshold = 1000 }) => pruneThreshold
const getDeriveSeries = ({ deriveModes = "" }) => {
  let deriveSeries = {}
  if (deriveModes !== ""){
    deriveModes.split("~").forEach(
      mode => (
        deriveSeries["-" + mode] = mode
      )
    )
  }
  return deriveSeries
}
const getDeriveWindowSecs = ({ deriveWindowSecs = 120 }) => deriveWindowSecs

// Handles the basic metrics like Counter, LastValue, and Sum.
class CommonMetric {
  static __projections() {
    return {
      counter: (y, value) => value + 1,
      last_value: (y) => y,
      sum: (y, value) => value + y
    }
  }

  static getConfig(options) {
    return {
      class: options.kind,
      title: options.title,
      width: options.width,
      height: options.height,
      series: [
        { ...XSeriesValue() },
        newSeriesConfig(options, 0)
      ],
      scales: {
        x: {
          min: options.now - 60,
          max: options.now
        },
        y: {
          min: 0,
          max: 1
        },
      },
      axes: [
        XAxis(),
        YAxis(options)
      ]
    }
  }

  static initialData() {
    return [[], []]
  }

  constructor(chart, options) {
    this.__callback = this.constructor.__projections()[options.metric]
    this.chart = chart
    this.datasets = [{ key: "|x|", data: [] }]
    this.options = options
    this.pruneThreshold = getPruneThreshold(options)

    if (options.tagged) {
      this.chart.delSeries(1)
      this.__handler = nextTaggedValueForCallback
    } else {
      this.datasets.push({ key: options.label, data: [] })
      this.__handler = nextValueForCallback
    }
  }

  handleMeasurements(measurements) {
    // prune datasets when we reach the max number of events
    measurements.forEach((measurement) => this.__handler.call(this, measurement, this.__callback))

    let currentSize = this.datasets[0].data.length
    if (currentSize >= this.pruneThreshold) {
      this.datasets = this.datasets.map(({ data, ...rest }) => {
        return { data: data.slice(-this.pruneThreshold), ...rest }
      })
    }

    this.chart.setData(dataForDatasets(this.datasets))
  }
}

// Displays a measurement summary
class Summary {
  constructor(options, chartEl) {
    // TODO: Get percentiles from options
    let config = this.constructor.getConfig(options)
    // Bind the series `values` callback to this instance
    config.series[1].values = this.__seriesValues.bind(this)

    this.datasets = [{ key: "|x|", data: [], derived: {from: -1, mode: "", dataRaw: []}}]
    this.chart = new uPlot(config, this.constructor.initialData(options), chartEl)
    this.pruneThreshold = getPruneThreshold(options)
    this.options = options
    this.options.deriveSeries = getDeriveSeries(options)
    this.options.deriveWindowSecs = getDeriveWindowSecs(options)

    if (options.tagged) {
      this.chart.delSeries(1)
      this.__handler = this.handleTaggedMeasurement.bind(this)
    } else {
      this.datasets.push(this.constructor.newDataset(options.label, -1, "", 0))
      Object.entries(this.options.deriveSeries).forEach(
        entry => {
          let [suffix, deriveMode] = entry
          this.findOrCreateSeries(options.label + suffix, 1, deriveMode)
        }
      )
      this.__handler = this.handleMeasurement.bind(this)
    }
  }

  handleMeasurements(measurements) {
    measurements.forEach((measurement) => this.__handler(measurement))
    this.__maybePruneDatasets()
    this.chart.setData(dataForDatasets(this.datasets))
  }

  handleTaggedMeasurement(measurement) {
    let rootSeriesIndex = this.findOrCreateSeries(measurement.x, -1, "")

    //handle derived series creation
    Object.entries(this.options.deriveSeries).forEach(
        entry => {
            let [suffix, deriveMode] = entry 
            let label = measurement.x + suffix
            //we create the series here. the update will be handeled below
            this.findOrCreateSeries(label, rootSeriesIndex, deriveMode)
        }
    )

    //actually do the measurements
    this.handleMeasurement(measurement, rootSeriesIndex)
  }

  handleMeasurement(measurement, sidx = 1) {
    let { z: timestamp } = measurement
    this.datasets = this.datasets.map((dataset, index) => {
      if (dataset.key === "|x|") {
        dataset.data.push(timestamp)
      } else if (index === sidx || dataset.derived.from === sidx) {
        this.pushToDataset(dataset, measurement)
      } else {
         this.pushToDataset(dataset, null)
      }
      return dataset
    })
  }

  findOrCreateSeries(label, derivedFrom, deriveMode) {
    let seriesIndex = this.datasets.findIndex(({ key }) => label === key)
    if (seriesIndex === -1) {
      seriesIndex = this.datasets.push(
        this.constructor.newDataset(label, derivedFrom, deriveMode, this.datasets[0].data.length)
      ) - 1

      let config = {
        values: this.__seriesValues.bind(this),
        ...newSeriesConfig({ label }, seriesIndex - 1)
      }

      this.chart.addSeries(config, seriesIndex)
    }

    return seriesIndex
  }

  pushToDataset(dataset, measurement) {
    if (measurement === null) {
      dataset.data.push(null)
      dataset.agg.avg.push(null)
      dataset.agg.max.push(null)
      dataset.agg.min.push(null)

      if (dataset.derived.from !== -1){
        dataset.derived.dataRaw.push(null)
      }

      return
    }

    var { y, z: timestamp } = measurement

    // Increment the new overall totals
    dataset.agg.count++

    if (dataset.derived.from !== -1) {
        // Push the raw value
        dataset.derived.dataRaw.push(measurement)
        let mode = dataset.derived.mode
        if (mode !== undefined && mode !== ""){
            // perform windowing
            let windowedData = dataset.derived.dataRaw.filter(v => {
                if (v !== null){
                    return v.z >= (timestamp - this.options.deriveWindowSecs)
                }
                return false
                }
            ).map(
                v => {
                    return v.y
                }
            )
            let isPercentile = mode[0] == "p"
            if (isPercentile) {
                let percTarget = parseInt(mode.slice(1))
                let sortedData = Array.from(windowedData).sort()
                let dataLength = sortedData.length
                let idx = Math.floor((percTarget / 100) * (dataLength - 1))
                y = sortedData[idx]
            } else if (mode == "mean"){
                //mean
                const reducer = (x,y) => x+y
                y = windowedData.reduce(reducer) / windowedData.length
            } else {
                console.error("Unknown deriveMode")
            }
        }
    }

    //Push the usable value (potentially derived)
    dataset.data.push(y)

    dataset.agg.total += y
    // Push min/max/avg
    if (dataset.last.min === null || y < dataset.last.min) { dataset.last.min = y }
    dataset.agg.min.push(dataset.last.min)

    if (dataset.last.max === null || y > dataset.last.max) { dataset.last.max = y }
    dataset.agg.max.push(dataset.last.max)

    dataset.agg.avg.push((dataset.agg.total / dataset.agg.count))

    return dataset
  }

  __maybePruneDatasets() {
    let currentSize = this.datasets[0].data.length

    if (currentSize > this.pruneThreshold) {
      let start = -this.pruneThreshold;
      this.datasets = this.datasets.map(({ key, data, derived, agg }) => {
        let dataPruned = data.slice(start)
        let derivedDataRawPruned = derived.dataRaw.slice(start)


        let derivedPruned = {
            from: derived.from,
            mode: derived.mode,
            dataRaw: derivedDataRawPruned
        }

        if (!agg) {
          return { key, data: dataPruned, derived: derivedPruned}
        }

        let { avg, count, max, min, total } = agg
        let minPruned = min.slice(start)
        let maxPruned = max.slice(start)

        return {
          key, 
          data: dataPruned,
          derived: derivedPruned,
          agg: {
            avg: avg.slice(start),
            count,
            min: minPruned,
            max: maxPruned,
            total
          },
          last: {
            min: findLastNonNullValue(minPruned),
            max: findLastNonNullValue(maxPruned)
          }
        }
      })
    }
  }

  __seriesValues(u, sidx, idx) {
    let dataset = this.datasets[sidx]
    if (dataset && dataset.data && dataset.data[idx]) {
      let { agg: { avg, max, min }, data } = dataset
      return {
        Value: data[idx].toFixed(3),
        Min: min[idx].toFixed(3),
        Max: max[idx].toFixed(3),
        Avg: avg[idx].toFixed(3)
      }
    } else {
      return { Value: "--", Min: "--", Max: "--", Avg: "--" }
    }
  }

  static initialData() { return [[], []] }

  static getConfig(options) {
    return {
      class: options.kind,
      title: options.title,
      width: options.width,
      height: options.height,
      series: [
        { ...XSeriesValue() },
        newSeriesConfig(options, 0)
      ],
      scales: {
        x: {
          min: options.now - 60,
          max: options.now
        },
        y: {
          min: 0,
          max: 1
        },
      },
      axes: [
        XAxis(),
        YAxis(options)
      ]
    }
  }

  static newDataset(key, derivedFrom, deriveMode, length = 0) {
    let nils = length > 0 ? Array(length).fill(null) : []
    return {
      key,
      derived: {
        from: derivedFrom,
        mode: deriveMode,
        dataRaw: (derivedFrom !== -1) ? [...nils] : [],
      },
      data: [...nils],
      agg: { avg: [...nils], count: 0, max: [...nils], min: [...nils], total: 0 },
      last: { max: null, min: null }
    }
  }
}

const __METRICS__ = {
  counter: CommonMetric,
  last_value: CommonMetric,
  sum: CommonMetric,
  summary: Summary
}

export class TelemetryChart {
  constructor(chartEl, options) {
    if (!options.metric) {
      throw new TypeError(`No metric type was provided`)
    } else if (options.metric && !__METRICS__[options.metric]) {
      throw new TypeError(`No metric defined for type ${options.metric}`)
    }

    const metric = __METRICS__[options.metric]
    if (metric === Summary) {
      this.metric = new Summary(options, chartEl)
      this.uplotChart = this.metric.chart
    } else {
      this.uplotChart = new uPlot(metric.getConfig(options), metric.initialData(options), chartEl)
      this.metric = new metric(this.uplotChart, options)
    }

    // setup the data buffer
    let isBufferingData = typeof options.refreshInterval !== "undefined"
    this._isBufferingData = isBufferingData
    this._buffer = []
    this._timer = isBufferingData ? setInterval(
      this._flushToChart.bind(this),
      +options.refreshInterval
    ) : null
  }

  clearTimers() { clearInterval(this._timer) }

  resize(boundingBox) {
    this.uplotChart.setSize({
      width: Math.max(boundingBox.width, minChartSize.width),
      height: minChartSize.height
    })
  }

  pushData(measurements) {
    if (!measurements.length) return
    let callback = this._isBufferingData ? this._pushToBuffer : this._pushToChart
    callback.call(this, measurements)
  }

  _pushToBuffer(measurements) {
    this._buffer = this._buffer.concat(measurements)
  }

  _pushToChart(measurements) {
    this.metric.handleMeasurements(measurements)
  }

  // clears the buffer and pushes the measurements
  _flushToChart() {
    let measurements = this._flushBuffer()
    if (!measurements.length) { return }
    this._pushToChart(measurements)
  }

  // clears and returns the buffered data as a flat array
  _flushBuffer() {
    if (this._buffer && !this._buffer.length) { return [] }
    let measurements = this._buffer
    this._buffer = []
    return measurements.reduce((acc, val) => acc.concat(val), [])
  }
}

/** LiveView Hook **/

const PhxChartComponent = {
  mounted() {
    let chartEl = this.el.parentElement.querySelector('.chart')
    let size = chartEl.getBoundingClientRect()
    let options = Object.assign({}, chartEl.dataset, {
      tagged: (chartEl.dataset.tags && chartEl.dataset.tags !== "") || false,
      width: Math.max(size.width, minChartSize.width),
      height: minChartSize.height,
      now: new Date() / 1e3,
      refreshInterval: 1000
    })

    this.chart = new TelemetryChart(chartEl, options)

    window.addEventListener("resize", throttle(() => {
      let newSize = chartEl.getBoundingClientRect()
      this.chart.resize(newSize)
    }))
  },
  updated() {
    const data = Array
      .from(this.el.children || [])
      .map(({ dataset: { x, y, z } }) => {
        // converts y-axis value (z) to number,
        // converts timestamp (z) from µs to fractional seconds
        return { x, y: +y, z: +z / 1e6 }
      })

    if (data.length > 0) {
      this.chart.pushData(data)
    }
  },
  destroyed() {
    this.chart.clearTimers()
  }
}

export default PhxChartComponent
