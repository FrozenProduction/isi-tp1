<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
<xsl:output method="html" encoding="UTF-8" indent="no"/>
<xsl:template match="/">
<html lang="pt-PT">
<head>
<meta charset="utf-8"/>
<title>TP1 ISI - Precos de combustiveis por distrito</title>
<style>
body { font-family: Arial, Helvetica, sans-serif; font-size: 13px; color: #222222; }
table { border-collapse: collapse; width: 100%; }
th, td { border: 1px solid #bbbbbb; padding: 4px 6px; text-align: left; }
th { background-color: #333333; color: #ffffff; }
tr:nth-child(even) { background-color: #f3f3f3; }
</style>
</head>
<body>
<h2>TP1 ISI - Agregados de precos de combustiveis por distrito</h2>
<p>Relatorio gerado pelo JOB_TP1 (exportacao XML do modelo + transformacao XSLT). Uma linha por distrito e combustivel: numero de postos, preco medio, minimo e maximo, e o desvio em relacao a media nacional do mesmo combustivel.</p>
<table>
<tr>
<th>Distrito</th>
<th>Combustivel</th>
<th>Unidade</th>
<th>Postos</th>
<th>Preco medio</th>
<th>Preco minimo</th>
<th>Preco maximo</th>
<th>Desvio media nacional</th>
</tr>
<xsl:for-each select="agregados/agregado">
<tr>
<td><xsl:value-of select="distrito"/></td>
<td><xsl:value-of select="combustivel"/></td>
<td><xsl:value-of select="unidade"/></td>
<td><xsl:value-of select="n_postos"/></td>
<td><xsl:value-of select="preco_medio"/></td>
<td><xsl:value-of select="preco_min"/></td>
<td><xsl:value-of select="preco_max"/></td>
<td><xsl:value-of select="desvio_media_nacional"/></td>
</tr>
</xsl:for-each>
</table>
<p>Ficheiros desta execucao: agg_distrito_combustivel.csv, .json, .xml e .sql (pasta dados/export).</p>
</body>
</html>
</xsl:template>
</xsl:stylesheet>
