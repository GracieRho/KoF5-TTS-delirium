import { useCallback, useEffect, useRef, useState } from 'react'
import { useAuth } from '../../shared/auth/AuthContext'
import { RequestEpoch } from '../../shared/hooks/requestEpoch'
import { careApi, EMPTY_CARE, type CareData } from './api'
export function useHospitalCare() {
 const {api,token} = useAuth()
 const [data,setData] = useState<CareData>(EMPTY_CARE)
 const [loading,setLoading] = useState(true), [error,setError] = useState(''), [notice,setNotice] = useState(''), [busy,setBusy] = useState(false)
 const requests=useRef(new RequestEpoch()), lock=useRef(false), mounted=useRef(true)
 const refresh=useCallback(async () => {
  if (!api||!token) return
  const epoch=requests.current.begin(); setLoading(true)
  try { const rows=await careApi.load(api,token); if(requests.current.owns(epoch)) {setData(rows);setError('')} }
  catch(error) {if(requests.current.owns(epoch)) {setError(error instanceof Error ? error.message : '돌봄 기록을 불러오지 못했습니다.');setData(EMPTY_CARE)} }
  finally {if(requests.current.owns(epoch)) setLoading(false)}
 },[api,token])
 useEffect(() => {mounted.current=true;setData(EMPTY_CARE);void refresh();return () => {mounted.current=false;requests.current.invalidate()}},[refresh])
 async function save(table: 'care_note'|'care_task'|'care_voice_schedule', body:unknown, id?:string, version?:number):Promise<boolean> {
  if(!api||!token||lock.current) return false
  lock.current=true;setBusy(true);setNotice('')
  try {await careApi.write(api,token,table,body,id,version);if(mounted.current) {await refresh();setNotice('기록을 저장했습니다.')}return true}
  catch(error) {if(mounted.current) {setNotice(error instanceof Error ? error.message : '저장하지 못했습니다.');await refresh()}return false}
  finally {lock.current=false;if(mounted.current)setBusy(false)}
 }
 return {data,loading,error,notice,busy,refresh,save}
}
