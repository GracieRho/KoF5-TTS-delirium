import {expect,it} from 'vitest'
import {readHospitalRoute,hospitalRouteSearch} from './navigation'
it('작업 대상·목록 검색과 스크롤을 URL 왕복에서 유지한다',()=>{
 const route={...readHospitalRoute(''),view:'patients' as const,patient:'id',tab:'voice' as const,record:'plan-1',query:'김 하늘',ward:'햇살',filter:'overdue',scroll:540}
 expect(readHospitalRoute(hospitalRouteSearch(route))).toEqual(route)
})
it('지원하지 않는 전역·환자 탭은 담당 환자와 개요로 복구한다',()=>{
 expect(readHospitalRoute('?view=dashboard&tab=missing&scroll=-5')).toMatchObject({view:'patients',tab:'overview',scroll:0})
})
