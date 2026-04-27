INSTALL spatial;
INSTALL httpfs;

LOAD spatial;
LOAD httpfs;

CREATE OR REPLACE TABLE my_buildings AS
SELECT *
FROM ST_Read('map.GeoJSON');

SELECT COUNT(*) AS my_buildings_count
FROM my_buildings;

CREATE OR REPLACE TABLE links AS
WITH raw_data AS (
    SELECT *
    FROM 'https://stac.overturemaps.org/2026-04-15.0/buildings/building/collection.json'
),
raw_links AS (
    SELECT unnest(links) AS link
    FROM raw_data
),
links AS (
    SELECT
        row_number() OVER () AS id,
        link.href AS href
    FROM raw_links
    WHERE link.type = 'application/geo+json'
),
raw_bboxes AS (
    SELECT unnest(extent.spatial.bbox) AS bbox
    FROM raw_data
),
bboxes AS (
    SELECT
        row_number() OVER () AS id,
        bbox[1] AS xmin,
        bbox[2] AS ymin,
        bbox[3] AS xmax,
        bbox[4] AS ymax
    FROM raw_bboxes
)
SELECT
    links.href,
    bboxes.xmin,
    bboxes.ymin,
    bboxes.xmax,
    bboxes.ymax
FROM links
JOIN bboxes ON links.id = bboxes.id;

SET VARIABLE item_url = (
    WITH my_bbox AS (
        SELECT ST_Extent_Agg(geom) AS geom
        FROM my_buildings
    ),
    bbox AS (
        SELECT
            ST_Xmin(geom) AS xmin,
            ST_Ymin(geom) AS ymin,
            ST_Xmax(geom) AS xmax,
            ST_Ymax(geom) AS ymax
        FROM my_bbox
    )
    SELECT DISTINCT
        'https://stac.overturemaps.org/2026-04-15.0/buildings/building/' || links.href
    FROM links, bbox
    WHERE NOT (
        links.xmax < bbox.xmin OR
        links.xmin > bbox.xmax OR
        links.ymax < bbox.ymin OR
        links.ymin > bbox.ymax
    )
    LIMIT 1
);

SET VARIABLE s3_href = (
    SELECT assets.aws.alternate.s3.href
    FROM read_json(getvariable('item_url'))
);

CREATE OR REPLACE TABLE overture_buildings_raw AS
WITH my_bbox_geom AS (
    SELECT ST_Extent_Agg(geom) AS geom
    FROM my_buildings
),
my_bbox AS (
    SELECT
        ST_Xmin(geom) AS xmin,
        ST_Ymin(geom) AS ymin,
        ST_Xmax(geom) AS xmax,
        ST_Ymax(geom) AS ymax
    FROM my_bbox_geom
)
SELECT
    data.* EXCLUDE geometry,
    data.geometry
FROM read_parquet(getvariable('s3_href')) AS data
JOIN my_bbox
ON ST_Xmin(data.geometry) BETWEEN my_bbox.xmin AND my_bbox.xmax
AND ST_Ymin(data.geometry) BETWEEN my_bbox.ymin AND my_bbox.ymax
WHERE try(ST_IsValid(data.geometry)) = true;

CREATE OR REPLACE TABLE overture_buildings AS
SELECT DISTINCT ON (o.id)
    o.geometry,
    o.id,
    o.class,
    o.height,
    CASE
        WHEN m.geom IS NOT NULL THEN 'my'
        WHEN list_contains(list_transform(o.sources, s -> s.dataset), 'OpenStreetMap') THEN 'osm'
        ELSE 'ml'
    END AS source_type
FROM overture_buildings_raw o
LEFT JOIN my_buildings m
ON try(ST_Intersects(m.geom, ST_SetCRS(o.geometry, 'EPSG:4326'))) = true;

SELECT source_type, COUNT(*) AS count
FROM overture_buildings
GROUP BY source_type;

COPY (
    SELECT json_object(
        'type', 'FeatureCollection',
        'features', json_group_array(
            json_object(
                'type', 'Feature',
                'geometry', ST_AsGeoJSON(ST_SetCRS(geometry, 'EPSG:4326'))::JSON,
                'properties', json_object(
                    'id', id,
                    'source_type', source_type,
                    'class', class,
                    'height', height
                )
            )
        )
    )
    FROM overture_buildings
)
TO 'lab2/client/client/public/overture.geojson'
WITH (FORMAT CSV, HEADER false, QUOTE '');