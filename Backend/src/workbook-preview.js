import { ServiceError } from './validation.js';

const escape = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const themes = ['#ffffff','#000000','#e7e6e6','#44546a','#4472c4','#ed7d31','#a5a5a5','#ffc000','#5b9bd5','#70ad47'];
function color(value, fallback) {
  if (value?.argb && /^[0-9a-f]{6,8}$/i.test(value.argb)) return `#${value.argb.slice(-6)}`;
  return themes[value?.theme] || fallback;
}
function fontStyle(font = {}) {
  return [`font-family:${String(font.name || 'Arial').replace(/[^\p{L}\p{N} ,_-]/gu,'')},sans-serif`,
    `font-size:${Math.min(100,Math.max(6,Number(font.size)||11))*4/3}px`,
    `color:${color(font.color,'#20252b')}`,font.bold?'font-weight:700':'',font.italic?'font-style:italic':'',
    font.underline?'text-decoration:underline':''].filter(Boolean).join(';');
}
function cellStyle(cell) {
  const style = [fontStyle(cell.font)];
  style.push(`background:${color(cell.fill?.fgColor,'#ffffff')}`);
  const align=cell.alignment||{};
  style.push(`text-align:${['left','right','center','justify'].includes(align.horizontal)?align.horizontal:typeof cell.value==='number'?'right':'left'}`);
  style.push(`vertical-align:${({middle:'middle',bottom:'bottom',top:'top'})[align.vertical]||'bottom'}`);
  style.push(align.wrapText?'white-space:pre-wrap':'white-space:pre');
  for(const side of ['top','right','bottom','left']){
    const border=cell.border?.[side];
    if(border?.style)style.push(`border-${side}:${['medium','thick','double'].includes(border.style)?2:1}px ${border.style==='double'?'double':border.style==='dashed'?'dashed':'solid'} ${color(border.color,'#76808c')}`);
  }
  return style.join(';');
}
function valueText(cell) {
  const value=cell.value;
  if(value instanceof Date)return value.toISOString().slice(0,10);
  const result=value&&typeof value==='object'&&'formula' in value?value.result:value;
  if(typeof result==='number'&&cell.numFmt&&cell.numFmt!=='General'){
    const fmt=cell.numFmt;
    const decimals=Math.min(8,(fmt.match(/\.(0+)/)?.[1]||'').length);
    const number=fmt.includes('%')?result*100:result;
    const text=new Intl.NumberFormat('zh-CN',{minimumFractionDigits:decimals,maximumFractionDigits:decimals,useGrouping:fmt.includes(',')}).format(number);
    const currency=fmt.includes('¥')||fmt.includes('￥')?'¥':fmt.includes('$')?'$':'';
    return currency+text+(fmt.includes('%')?'%':'');
  }
  return cell.text;
}
function cellContent(cell) {
  if(cell.value?.richText)return cell.value.richText.map(run=>`<span style="${escape(fontStyle(run.font))}">${escape(run.text)}</span>`).join('');
  return escape(valueText(cell));
}

export async function workbookPreview(buffer) {
  const { default: ExcelJS } = await import('exceljs');
  const book=new ExcelJS.Workbook();
  try { await book.xlsx.load(buffer); } catch { throw new ServiceError('工作簿无法读取，请使用原应用检查文件是否损坏或加密'); }
  const sheets=[];let limited=book.worksheets.length>10;
  for(const sheet of book.worksheets.slice(0,10)){
    const images=sheet.getImages();
    const maxImageRow=Math.max(0,...images.map(image=>Math.ceil(image.range.br?.row??(image.range.tl?.row||0)+20)));
    const maxImageCol=Math.max(0,...images.map(image=>Math.ceil(image.range.br?.col??(image.range.tl?.col||0)+10)));
    const rows=Math.min(400,Math.max(1,sheet.rowCount,maxImageRow)),cols=Math.min(60,Math.max(1,sheet.columnCount,maxImageCol));
    limited ||= sheet.rowCount>rows||sheet.columnCount>cols||maxImageRow>rows||maxImageCol>cols;
    const widths=Array.from({length:cols},(_,i)=>sheet.getColumn(i+1).hidden?0:Math.max(12,(sheet.getColumn(i+1).width||9)*7+5));
    const heights=Array.from({length:rows},(_,i)=>sheet.getRow(i+1).hidden?0:(sheet.getRow(i+1).height||15)*4/3);
    const sums=values=>values.reduce((all,v)=>[...all,all.at(-1)+v],[0]);
    const x=sums(widths),y=sums(heights);
    const position=(anchor,axis)=>{const v=Math.max(0,Number(anchor?.[axis])||0);const i=Math.min(Math.floor(v),axis==='col'?cols:rows);const sizes=axis==='col'?widths:heights;return (axis==='col'?x:y)[i]+(sizes[i]||0)*(v-i);};
    const merges=new Map((sheet.model.merges||[]).map(range=>{
      const [start,end]=range.split(':').map(address=>sheet.getCell(address));
      return [start.address,{colspan:Math.min(cols,end.col)-start.col+1,rowspan:Math.min(rows,end.row)-start.row+1}];
    }));
    let table='<colgroup>'+widths.map(w=>`<col style="width:${w}px">`).join('')+'</colgroup>';
    for(let row=1;row<=rows;row++){
      table+=`<tr style="height:${heights[row-1]}px;${heights[row-1]===0?'display:none':''}">`;
      for(let col=1;col<=cols;col++){
        const cell=sheet.getCell(row,col);
        if(cell.isMerged&&cell.master.address!==cell.address)continue;
        const merge=merges.get(cell.address);
        table+=`<td${merge?` colspan="${merge.colspan}" rowspan="${merge.rowspan}"`:''} style="${escape(cellStyle(cell))};${widths[col-1]===0?'display:none':''}">${cellContent(cell)}</td>`;
      }
      table+='</tr>';
    }
    let graphics='';
    for(const image of images){
      const source=book.getImage(image.imageId),extension=source.extension?.toLowerCase();
      if(!['png','jpeg','jpg','gif','webp'].includes(extension)){limited=true;continue;}
      const data=source.buffer?Buffer.from(source.buffer).toString('base64'):String(source.base64||'').replace(/^data:[^,]+,/,'');
      if(!data){limited=true;continue;}
      const left=position(image.range.tl,'col'),top=position(image.range.tl,'row');
      const width=image.range.ext?.width??position(image.range.br,'col')-left;
      const height=image.range.ext?.height??position(image.range.br,'row')-top;
      graphics+=`<img alt="工作簿内嵌图片" src="data:image/${extension==='jpg'?'jpeg':extension};base64,${data}" style="position:absolute;left:${left}px;top:${top}px;width:${Math.max(1,width)}px;height:${Math.max(1,height)}px">`;
    }
    sheets.push(`<section><h2>${escape(sheet.name)}</h2><div class="sheet-scroll"><div class="sheet" style="width:${x.at(-1)}px;min-height:${y.at(-1)}px"><table style="width:${x.at(-1)}px">${table}</table>${graphics}</div></div></section>`);
  }
  const notice=limited?'预览最多显示前 10 个工作表、各表前 400 行和 60 列；部分内容超出预览范围，请打开原文件查看。':'复杂图表、条件格式及打印分页请在原应用中查看。';
  const scrollbars='::-webkit-scrollbar{width:6px;height:6px;background:transparent}::-webkit-scrollbar-track,::-webkit-scrollbar-corner{background:transparent;border:0;box-shadow:none}::-webkit-scrollbar-thumb{background:rgba(32,36,43,.3);border:0;border-radius:3px;box-shadow:none}';
  return `<!doctype html><html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><style>${scrollbars}body{margin:0;padding:18px;background:#f4f6f8;color:#233345;font:13px -apple-system,sans-serif}h2{font-size:14px;margin:0 0 12px}section{padding:18px;margin-bottom:16px;background:white;border:1px solid #dae0e6;border-radius:6px}.sheet-scroll{overflow:auto}.sheet{position:relative}table{border-collapse:collapse;table-layout:fixed}td{box-sizing:border-box;border:1px solid #d4d8de;padding:2px 4px;overflow:hidden}img{object-fit:fill}.notice{color:#66717e;margin:0 0 16px}</style></head><body><p class="notice">${notice}</p>${sheets.join('')}</body></html>`;
}
