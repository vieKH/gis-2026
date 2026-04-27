import './style.css';

import 'ol/ol.css';

import Map from 'ol/Map';
import View from 'ol/View';
import TileLayer from 'ol/layer/Tile';

import OSM from 'ol/source/OSM';

import ImageLayer from 'ol/layer/Image';
import ImageWMS from 'ol/source/ImageWMS';
import { fromLonLat } from 'ol/proj';
import { apply } from 'ol-mapbox-style';

const pointCenter = fromLonLat([109.220, 13.768]);

const map = new Map({
  target: 'map',
  layers: [
    new TileLayer({
      source: new OSM()
    }),

    new ImageLayer({
      source: new ImageWMS({
        url: 'http://localhost:8080/geoserver/gis/wms',
        params: {
          LAYERS: 'gis:buildings',
          TILED: true
        },
        ratio: 1,
        serverType: 'geoserver'
      })
    }),

    new ImageLayer({
      source: new ImageWMS({
        url: 'http://localhost:8080/geoserver/gis/wms',
        params: {
          LAYERS: 'gis:roads',
          TILED: true
        },
        ratio: 1,
        serverType: 'geoserver'
      })
    })
  ],
  view: new View({
    center: pointCenter,
    zoom: 18
  })
});

fetch('/mapbox-style.json')
  .then((response) => response.json())
  .then((style) => {
    apply(map, style);
  })
  .catch((error) => {
    console.error('Cannot load Mapbox style:', error);
  });