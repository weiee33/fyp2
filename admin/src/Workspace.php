<?php
declare(strict_types=1);
namespace LocalLife;

final class Workspace
{
    /** Retain list context without accepting an arbitrary redirect destination. */
    public static function filters(array $query): array
    {
        $result=[];
        foreach (['q','status','p'] as $key) {
            if (isset($query[$key]) && is_string($query[$key]) && $query[$key]!=='') { $result[$key]=$query[$key]; }
        }
        return $result;
    }

    public static function resource(SupabaseClient $api, string $page, array $query): array
    {
        $data=$api->rpc('admin_list',['resource'=>$page,'search'=>mb_substr((string)($query['q'] ?? ''),0,100),'status_filter'=>(string)($query['status'] ?? ''),'page_number'=>max(1,(int)($query['p'] ?? 1))]);
        $detail=empty($query['id'])?null:$api->rpc('admin_detail',['resource'=>$page,'record_id'=>Security::uuid((string)$query['id'])]);
        $choices=[];
        if ($page==='categories') {
            for ($i=1;$i<=100;$i++) {
                $chunk=$api->rpc('admin_list',['resource'=>'categories','page_number'=>$i]);
                $choices=array_merge($choices,$chunk['items']);
                if (count($choices)>=$chunk['total'] || !$chunk['items']) { break; }
            }
        }
        return [$data,$detail,$choices];
    }

    public static function recovery(array $post): array
    {
        // Never restore CSRF, concurrency versions, hidden authorization fields or files.
        $values=array_intersect_key($post,array_flip(['reason','status','name','description','color','parent_id','display_order','decision','subject','amount','active']));
        return ['action'=>$post['action'] ?? '', 'recordId'=>$post['record_id'] ?? '', 'values'=>array_filter($values,'is_string')];
    }
}
