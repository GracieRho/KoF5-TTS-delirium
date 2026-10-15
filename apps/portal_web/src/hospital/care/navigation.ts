export type CareTab = 'overview'|'observations'|'plan'|'voice'|'handoff'
export type HospitalView = 'patients'|'voice'|'handoff'
export type HospitalRoute = {view:HospitalView;patient:string;tab:CareTab;record:string;voice:'plans'|'messages';query:string;ward:string;filter:string;scroll:number}
export function readHospitalRoute(search=window.location.search):HospitalRoute {
 const params=new URLSearchParams(search),view=params.get('view'),tab=params.get('tab')
 return {view:view==='voice'||view==='handoff'?view:'patients',patient:params.get('patient')||'',tab:['observations','plan','voice','handoff'].includes(tab||'')?tab as CareTab:'overview',record:params.get('record')||'',voice:params.get('voice')==='messages'?'messages':'plans',query:params.get('query')||'',ward:params.get('ward')||'',filter:params.get('filter')||'all',scroll:Math.max(0,Number(params.get('scroll'))||0)}
}
export function hospitalRouteSearch(route:HospitalRoute) {
 const params=new URLSearchParams()
 for(const [key,value] of Object.entries(route))if(value!==''&&value!==0)params.set(key,String(value))
 return `?${params}`
}
