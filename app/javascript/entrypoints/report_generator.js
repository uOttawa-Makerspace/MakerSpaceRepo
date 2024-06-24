import "chartkick/chart.js";

let Chart = Chartkick.adapters[0].library;
window.AChart = Chart;
// Add percentages to legend
Chart.overrides["pie"].plugins.legend.labels.generateLabels = (chart) => {
  const datasets = chart.data.datasets;
  let sum = 0;
  for (let data of datasets[0].data) {
    sum += data;
  }
  return datasets[0].data.map((data, i) => ({
    text: `${chart.data.labels[i]} ${((data * 100) / sum).toFixed(2)}%`,
    fillStyle: datasets[0].backgroundColor[i],
    index: i,
  }));
};

// Add percentages to everything else
// Since above doesn't apply to bar charts
Chart.defaults.plugins.tooltip.callbacks.afterTitle = (item) => {
  let chart = item[0];
  let sum = 0;
  for (let data of chart.dataset.data) {
    sum += data;
  }
  let thisPoint = chart.dataset.data[chart.dataIndex];
  return ((thisPoint * 100) / sum).toFixed(2) + "%";
};
